#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCES_DIR="${SCRIPT_DIR}/instances"
BASE_PORT=18789
DEFAULT_VERSION="latest"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

instance_dir() { echo "${INSTANCES_DIR}/$1"; }

require_instance() {
    local name="$1"
    [[ -d "$(instance_dir "$name")" ]] || die "Instance '$name' does not exist."
}

load_env() {
    local name="$1"
    local envfile="$(instance_dir "$name")/.env"
    [[ -f "$envfile" ]] || die "No .env found for instance '$name'."
    # shellcheck disable=SC1090
    source "$envfile"
}

next_free_port() {
    local port=$BASE_PORT
    local used_ports=()
    if [[ -d "$INSTANCES_DIR" ]]; then
        while IFS= read -r envfile; do
            local p
            p=$(grep -Po '(?<=^PORT=)\d+' "$envfile" 2>/dev/null || true)
            [[ -n "$p" ]] && used_ports+=("$p")
        done < <(find "$INSTANCES_DIR" -maxdepth 2 -name ".env")
    fi
    while printf '%s\n' "${used_ports[@]}" | grep -qx "$port"; do
        (( port++ ))
    done
    echo "$port"
}

project_name() { echo "openclaw-$1"; }

compose() {
    local name="$1"; shift
    docker compose -p "$(project_name "$name")" \
        -f "$(instance_dir "$name")/docker-compose.yml" \
        --env-file "$(instance_dir "$name")/.env" \
        "$@"
}

write_compose() {
    local dir="$1"
    cat > "${dir}/docker-compose.yml" <<'YAML'
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}
    container_name: openclaw-${NAME}
    ports:
      - "0.0.0.0:${PORT}:18789"
    volumes:
      - ./config:/home/node/.openclaw
      - ${WORKSPACE_PATH}:/home/node/.openclaw/workspace
    command: ["node", "openclaw.mjs", "gateway", "--allow-unconfigured", "--bind", "lan"]
    restart: unless-stopped
    user: "1000:1000"

  openclaw-cli:
    image: ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}
    profiles: ["cli"]
    volumes:
      - ./config:/home/node/.openclaw
    user: "1000:1000"
YAML
}

write_env() {
    local dir="$1" name="$2" port="$3" workspace="$4" version="$5"
    cat > "${dir}/.env" <<EOF
NAME=${name}
PORT=${port}
WORKSPACE_PATH=${workspace}
OPENCLAW_VERSION=${version}
EOF
}

# ── helpers ──────────────────────────────────────────────────────────────────

patch_brand() {
    local name="$1"
    local container="openclaw-${name}"
    local label="${name^^} OPENCLAW"  # uppercase name + OPENCLAW, e.g. "BOB OPENCLAW"

    local jsfile
    jsfile=$(docker exec "$container" grep -rl 'brand-title">OPENCLAW' /app/dist/control-ui/assets/ 2>/dev/null | head -1)

    if [[ -z "$jsfile" ]]; then
        echo "WARN: Could not find UI bundle to patch brand name."
        return
    fi

    local tmpfile="/tmp/openclaw-ui-patch-${name}.js"
    docker cp "${container}:${jsfile}" "$tmpfile"
    sed -i "s|brand-title\">OPENCLAW<|brand-title\">${label}<|g" "$tmpfile"
    docker cp "$tmpfile" "${container}:${jsfile}"
    rm -f "$tmpfile"
    echo "Brand name patched to '${label}'."
}

# ── commands ─────────────────────────────────────────────────────────────────

cmd_create() {
    local name="" workspace="" port="" version="$DEFAULT_VERSION"

    [[ $# -ge 1 ]] || die "Usage: create <name> [--workspace <path>] [--port <port>] [--version <tag>]"
    name="$1"; shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workspace) workspace="$2"; shift 2 ;;
            --port)      port="$2";      shift 2 ;;
            --version)   version="$2";   shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Instance name must be alphanumeric (hyphens/underscores allowed)."
    local idir
    idir="$(instance_dir "$name")"
    [[ ! -d "$idir" ]] || die "Instance '$name' already exists."

    [[ -z "$port" ]] && port="$(next_free_port)"
    [[ -z "$workspace" ]] && workspace="${idir}/workspace"

    # Make workspace absolute
    [[ "$workspace" = /* ]] || workspace="${PWD}/${workspace}"

    echo "Creating instance '${name}' on port ${port} ..."
    mkdir -p "${idir}/config" "${idir}/workspace"
    [[ "$workspace" != "${idir}/workspace" ]] && mkdir -p "$workspace"

    chown -R 1000:1000 "${idir}/config" "$workspace" 2>/dev/null || \
        echo "WARN: Could not chown directories (may need sudo). Proceeding anyway."

    write_compose "$idir"
    write_env "$idir" "$name" "$port" "$workspace" "$version"

    echo "Running onboard wizard ..."
    compose "$name" run --rm openclaw-cli openclaw.mjs onboard

    echo "Configuring LAN access ..."
    compose "$name" run --rm --no-TTY openclaw-cli node openclaw.mjs config set \
        gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true
    compose "$name" run --rm --no-TTY openclaw-cli node openclaw.mjs config set \
        gateway.controlUi.allowInsecureAuth true
    compose "$name" run --rm --no-TTY openclaw-cli node openclaw.mjs config set \
        gateway.controlUi.dangerouslyDisableDeviceAuth true
    compose "$name" run --rm --no-TTY openclaw-cli node openclaw.mjs config set \
        ui.assistant.name "$name"

    echo "Starting gateway ..."
    compose "$name" up -d openclaw-gateway
    patch_brand "$name"

    echo ""
    cmd_info "$name"
}

cmd_delete() {
    local name="" purge=false

    [[ $# -ge 1 ]] || die "Usage: delete <name> [--purge]"
    name="$1"; shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --purge) purge=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    require_instance "$name"

    echo "Stopping and removing containers for '${name}' ..."
    compose "$name" down --remove-orphans 2>/dev/null || true

    if $purge; then
        echo "Purging instance directory ..."
        rm -rf "$(instance_dir "$name")"
        echo "Instance '${name}' deleted."
    else
        echo "Instance '${name}' stopped. Use --purge to also remove files."
    fi
}

cmd_start() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: start <name>"
    require_instance "$name"
    compose "$name" up -d openclaw-gateway
    echo "Instance '${name}' started."
}

cmd_stop() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: stop <name>"
    require_instance "$name"
    compose "$name" stop openclaw-gateway
    echo "Instance '${name}' stopped."
}

cmd_status() {
    local name="${1:-}"
    if [[ -n "$name" ]]; then
        require_instance "$name"
        compose "$name" ps
    else
        if [[ ! -d "$INSTANCES_DIR" ]] || [[ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]]; then
            echo "No instances found."
            return
        fi
        for idir in "${INSTANCES_DIR}"/*/; do
            local n
            n="$(basename "$idir")"
            echo "=== ${n} ==="
            compose "$n" ps 2>/dev/null || echo "(error reading status)"
        done
    fi
}

cmd_list() {
    if [[ ! -d "$INSTANCES_DIR" ]] || [[ -z "$(ls -A "$INSTANCES_DIR" 2>/dev/null)" ]]; then
        echo "No instances found."
        return
    fi

    printf "%-20s %-8s %-10s %-15s\n" "NAME" "PORT" "STATUS" "VERSION"
    printf "%-20s %-8s %-10s %-15s\n" "----" "----" "------" "-------"

    for idir in "${INSTANCES_DIR}"/*/; do
        local n
        n="$(basename "$idir")"
        local envfile="${idir}.env"
        local port="?" version="?"
        if [[ -f "$envfile" ]]; then
            port=$(grep -Po '(?<=^PORT=)\S+' "$envfile" 2>/dev/null || echo "?")
            version=$(grep -Po '(?<=^OPENCLAW_VERSION=)\S+' "$envfile" 2>/dev/null || echo "?")
        fi
        local status="stopped"
        if docker inspect "openclaw-${n}" &>/dev/null; then
            local running
            running=$(docker inspect "openclaw-${n}" --format '{{.State.Running}}' 2>/dev/null || echo "false")
            [[ "$running" == "true" ]] && status="running" || status="exited"
        fi
        printf "%-20s %-8s %-10s %-15s\n" "$n" "$port" "$status" "$version"
    done
}

cmd_info() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: info <name>"
    require_instance "$name"

    local NAME PORT WORKSPACE_PATH OPENCLAW_VERSION
    load_env "$name"

    local actual_ver="$OPENCLAW_VERSION"
    local container="openclaw-${name}"
    if docker inspect "$container" &>/dev/null; then
        local oci_ver
        oci_ver=$(docker inspect "$container" \
            --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null || true)
        [[ -n "$oci_ver" ]] && actual_ver="${OPENCLAW_VERSION} (${oci_ver})"
    fi

    echo "Instance:   ${NAME}"
    echo "Port:       ${PORT}"
    echo "Version:    ${actual_ver}"
    echo "Workspace:  ${WORKSPACE_PATH}"

    local container="openclaw-${name}"
    if docker inspect "$container" &>/dev/null; then
        local running
        running=$(docker inspect "$container" --format '{{.State.Running}}')
        local image_size started_at
        image_size=$(docker image ls "ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}" --format '{{.Size}}' 2>/dev/null || echo "?")
        started_at=$(docker inspect "$container" --format '{{.State.StartedAt}}' 2>/dev/null | cut -dT -f1,2 | tr T ' ' | cut -d. -f1)
        echo ""
        echo "--- Container ---"
        echo "Status:     $(docker inspect "$container" --format '{{.State.Status}}')"
        echo "Started:    ${started_at}"
        echo "Image size: ${image_size}"
        if [[ "$running" == "true" ]]; then
            local stats
            stats=$(docker stats "$container" --no-stream --format \
                "CPU={{.CPUPerc}}  MEM={{.MemUsage}} ({{.MemPerc}})  NET={{.NetIO}}  BLOCK={{.BlockIO}}  PIDs={{.PIDs}}" 2>/dev/null)
            echo "CPU/MEM:    ${stats}"
        fi
    fi

    echo ""
    echo "--- Dashboard ---"
    compose "$name" run --rm --no-TTY openclaw-cli openclaw.mjs dashboard --no-open 2>/dev/null || \
        echo "(Could not retrieve dashboard info — is the instance running?)"
}

cmd_login() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: login <name>"
    require_instance "$name"
    docker exec -it "openclaw-${name}" bash
}

cmd_update() {
    local name="" version=""

    [[ $# -ge 1 ]] || die "Usage: update <name> [--version <tag>]"
    name="$1"; shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    require_instance "$name"
    local idir
    idir="$(instance_dir "$name")"

    if [[ -n "$version" ]]; then
        # Update version in .env
        sed -i "s/^OPENCLAW_VERSION=.*/OPENCLAW_VERSION=${version}/" "${idir}/.env"
        echo "Version set to '${version}'."
    else
        echo "Updating to latest ..."
        sed -i "s/^OPENCLAW_VERSION=.*/OPENCLAW_VERSION=latest/" "${idir}/.env"
    fi

    echo "Pulling new image ..."
    compose "$name" pull openclaw-gateway

    echo "Restarting gateway ..."
    compose "$name" up -d openclaw-gateway
    patch_brand "$name"

    echo "Instance '${name}' updated."
}

cmd_version() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "Usage: version <name>"
    require_instance "$name"

    local container="openclaw-${name}"
    docker inspect "$container" &>/dev/null || die "Container '${container}' is not running."

    local ver
    ver=$(docker inspect "$container" \
        --format '{{index .Config.Labels "org.opencontainers.image.version"}}' 2>/dev/null || true)

    if [[ -z "$ver" ]]; then
        # Fallback: read from .env
        ver=$(grep -Po '(?<=^OPENCLAW_VERSION=)\S+' "$(instance_dir "$name")/.env" 2>/dev/null || echo "unknown")
        echo "${ver} (from .env — image label not found)"
    else
        echo "$ver"
    fi
}

# ── usage ─────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
OpenClaw multi-instance manager

Usage: $(basename "$0") <command> [options]

Commands:
  create <name> [--workspace <path>] [--port <port>] [--version <tag>]
                          Create and start a new instance
  delete <name> [--purge] Stop containers; --purge also removes files
  start  <name>           Start a stopped instance
  stop   <name>           Stop a running instance
  status [<name>]         Show container status (all or one)
  list                    List all instances with port/status/version
  info   <name>           Show dashboard URL, token, workspace, port, version
  login  <name>           Open a bash shell inside the container
  update <name> [--version <tag>]
                          Pull new image and restart (default: latest)
  version <name>          Print running container's image version
EOF
}

# ── dispatch ──────────────────────────────────────────────────────────────────

[[ $# -ge 1 ]] || { usage; exit 0; }

COMMAND="$1"; shift

case "$COMMAND" in
    create)  cmd_create  "$@" ;;
    delete)  cmd_delete  "$@" ;;
    start)   cmd_start   "$@" ;;
    stop)    cmd_stop    "$@" ;;
    status)  cmd_status  "$@" ;;
    list)    cmd_list    "$@" ;;
    info)    cmd_info    "$@" ;;
    login)   cmd_login   "$@" ;;
    update)  cmd_update  "$@" ;;
    version) cmd_version "$@" ;;
    help|-h|--help) usage ;;
    *) die "Unknown command: '${COMMAND}'. Run '$(basename "$0") help' for usage." ;;
esac
