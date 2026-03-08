# ClaWHub

OpenClaw 多实例管理脚本，基于 Docker Compose，支持在同一台机器上运行多个独立的 OpenClaw 实例，每个实例拥有独立的端口、工作区和配置。

## 依赖

- Bash 4+
- Docker（含 `docker compose` 插件）
- 运行用户需有 Docker 权限

## 快速开始

```bash
# 克隆仓库
git clone <repo-url> clawhub
cd clawhub

# 创建并启动一个实例
./clawhub.sh create alice

# 查看实例信息（Dashboard URL、Token 等）
./clawhub.sh info alice
```

## 命令参考

| 命令 | 说明 |
|------|------|
| `create <name> [选项]` | 创建并启动新实例 |
| `delete <name> [--purge]` | 停止容器；`--purge` 同时删除文件 |
| `start <name>` | 启动已停止的实例 |
| `stop <name>` | 停止运行中的实例 |
| `status [<name>]` | 查看容器状态（不指定名称则显示全部） |
| `list` | 列出所有实例（名称/端口/状态/版本） |
| `info <name>` | 显示 Dashboard URL、Token、端口、版本、资源用量 |
| `login <name>` | 进入容器的 Bash Shell |
| `update <name> [--version <tag>]` | 拉取新镜像并重启（默认：latest） |
| `version <name>` | 显示容器当前镜像版本 |

### create 选项

```bash
./clawhub.sh create <name> \
  [--workspace <绝对或相对路径>] \  # 默认：instances/<name>/workspace
  [--port <端口号>] \               # 默认：自动分配（从 18789 起）
  [--version <镜像标签>]            # 默认：latest
```

## 实例数据目录

每个实例的数据存放于 `instances/<name>/`：

```
instances/
└── alice/
    ├── .env               # 实例配置（端口、版本、工作区路径）
    ├── docker-compose.yml # 自动生成，勿手动修改
    ├── config/            # OpenClaw 配置（持久化）
    └── workspace/         # 用户工作区（持久化）
```

> `instances/` 目录内容已被 `.gitignore` 忽略，不会提交到版本库。

## 多实例示例

```bash
# 为不同用户各创建一个实例
./clawhub.sh create alice --workspace /data/alice
./clawhub.sh create bob   --workspace /data/bob

# 查看所有实例
./clawhub.sh list
# NAME                 PORT     STATUS     VERSION
# ----                 ----     ------     -------
# alice                18789    running    latest
# bob                  18790    running    latest

# 更新单个实例
./clawhub.sh update alice --version v1.2.0
```

## 注意事项

- 容器以 `uid 1000:1000` 运行，`config/` 和 `workspace/` 目录需可被该用户读写。若 `chown` 失败，脚本会给出警告但继续执行。
- `create` 和 `update` 后会自动将容器 UI 中的品牌名称替换为实例名称（如 `ALICE OPENCLAW`）。
- 端口从 `18789` 起自动递增，已被占用的端口会被跳过。
