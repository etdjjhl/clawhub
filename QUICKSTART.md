# ClawhHub Quickstart

## 新建实例

```bash
# 最简创建（端口自动分配，从 18789 开始递增）
clawhub create myinstance

# 指定 workspace 目录
clawhub create myinstance --workspace /data/projects

# 指定端口和版本
clawhub create myinstance --port 18790 --version 1.2.3
```

创建过程会自动完成：拉取镜像 → 运行 onboard 向导 → 写入配置 → 启动容器。
完成后自动打印 dashboard 信息（URL、token 等）。

---

## 访问 Dashboard

创建完成后，在浏览器打开：

```
http://<服务器IP>:<端口>
```

> 将 `<服务器IP>` 替换为实际服务器的 IP 地址，`<端口>` 默认从 `18789` 开始。

随时查询实例端口和访问信息：

```bash
clawhub list          # 所有实例：名称 / 端口 / 状态 / 版本
clawhub info myinstance  # 单个实例详情：URL、token、资源占用
```

---

## 配置文件和 Workspace 位置

所有实例数据默认存放在 `~/.local/share/clawhub/instances/<name>/`：

```
~/.local/share/clawhub/instances/myinstance/
├── .env                  # 端口、版本、workspace 路径等变量
├── docker-compose.yml    # 自动生成，无需手动编辑
├── config/               # OpenClaw 配置（挂载到容器 /home/node/.openclaw）
└── workspace/            # 默认 workspace（挂载到容器内）
```

> 如果创建时指定了 `--workspace /data/projects`，则 workspace 在该外部路径，
> `instances/myinstance/workspace/` 目录不会被使用。

查看当前 `CLAWHUB_HOME` 路径：

```bash
clawhub env
```

---

## 进入容器进行 OpenClaw 配置

**交互式 bash shell（推荐用于调试）：**

```bash
clawhub login myinstance
```

**通过 openclaw-cli 执行配置命令（配置写入持久化的 config/）：**

```bash
# 示例：设置某个配置项
docker compose -p openclaw-myinstance \
  -f ~/.local/share/clawhub/instances/myinstance/docker-compose.yml \
  --env-file ~/.local/share/clawhub/instances/myinstance/.env \
  run --rm --no-TTY openclaw-cli node openclaw.mjs config set <key> <value>
```

> `openclaw-cli` 服务使用 Docker profile `cli`，仅按需启动，不会常驻。

---

## 升级版本

```bash
# 升级到最新版本
clawhub update myinstance

# 升级到指定版本
clawhub update myinstance --version 1.5.0
```

升级过程：更新 `.env` 中的版本号 → 拉取新镜像 → 重启容器 → 重新应用 UI 品牌补丁。

---

## 其他常用操作

**启动 / 停止：**

```bash
clawhub start myinstance
clawhub stop myinstance
```

**删除实例：**

```bash
# 仅停止容器，保留配置和 workspace 文件
clawhub delete myinstance

# 彻底删除：停止容器 + 删除 instances/<name>/ 目录
clawhub delete myinstance --purge
```

> `--purge` 不会删除 `--workspace` 指定的外部目录，仅删除 `instances/<name>/` 下的托管文件。

**查看可用版本：**

```bash
clawhub versions       # 最近 7 天的发布版本
clawhub versions 30    # 最近 30 天
```

**查找游离容器（未被 clawhub 管理的 openclaw 容器）：**

```bash
clawhub orphans
```

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAWHUB_HOME` | `~/.local/share/clawhub` | 所有实例数据的根目录 |

可通过环境变量覆盖：

```bash
CLAWHUB_HOME=/opt/clawhub clawhub list
```
