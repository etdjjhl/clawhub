#!/usr/bin/env bash
# install-docker.sh
# Installs Docker Engine and the docker compose plugin on Ubuntu (22.04 / 24.04).
# Must be run as root or with sudo privileges.
set -euo pipefail

# ── colour helpers ────────────────────────────────────────────────────────────
info()  { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[1;32m[ OK ]\033[0m  $*"; }
die()   { echo -e "\033[1;31m[ERR ]\033[0m  $*" >&2; exit 1; }

# ── root check ────────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Please run as root: sudo bash $0"

# ── 1. system prerequisites ───────────────────────────────────────────────────
info "Updating package index ..."
apt-get update -qq

info "Installing prerequisites ..."
apt-get install -y -qq ca-certificates curl gnupg lsb-release

# ── 2. Docker GPG key ─────────────────────────────────────────────────────────
info "Adding Docker GPG key ..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# ── 3. Docker APT repository ──────────────────────────────────────────────────
info "Adding Docker APT repository ..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq

# ── 4. Install Docker Engine + Compose plugin ─────────────────────────────────
info "Installing Docker Engine, CLI, containerd, Buildx, and Compose plugin ..."
apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# ── 5. Enable and start Docker service ────────────────────────────────────────
info "Enabling Docker service ..."
systemctl enable --now docker

# ── 6. Add invoking user to the docker group (skip if already root) ───────────
INVOKING_USER="${SUDO_USER:-}"
if [[ -n "$INVOKING_USER" ]]; then
    info "Adding '${INVOKING_USER}' to the docker group ..."
    usermod -aG docker "$INVOKING_USER"
    ok "User '${INVOKING_USER}' added to docker group."
    echo "  NOTE: Log out and back in (or run 'newgrp docker') for group membership to take effect."
fi

# ── 7. Verify ─────────────────────────────────────────────────────────────────
info "Verifying installation ..."
docker --version
docker compose version

ok "Docker installation complete."
