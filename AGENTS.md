# AGENTS.md — AI Agent 使用指南

## 1. 项目简介

本项目是一个 **AI Agent 的编程工作台（Board）**，为 AI Agent（如 Hermes Agent）提供一个云端的代码开发环境。Agent 可以在此代码空间中编写代码、运行命令、完成任务，并将结果或报告通过 Telegram 等渠道发布。

核心组件：
- **OpenCode**：基于命令行的 AI 编程助手，以 server 模式运行，提供 HTTP API 供 Agent 调用。
- **Codespace**：云端开发环境，预配置了 Nix 包管理器、开发工具和 OpenCode 服务。

## 2. AI Agent 使用说明（通过 Codebox API 调用 OpenCode）

OpenCode 在此代码空间中以后台 server 模式运行（端口 `4096`），Agent 可以通过 HTTP API 与其交互。

### API 地址

```
http://<codespace-url>:4096
```

### 调用方式

Agent 向 OpenCode server 发送 API 请求，格式如下：

```json
{
  "messages": [
    {"role": "user", "content": "你的指令"}
  ]
}
```

示例（使用 curl）：

```bash
curl -X POST http://localhost:4096/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"列出当前目录文件"}]}'
```

OpenCode 会执行指令并返回结果。Agent 可以通过循环调用 API 来完成复杂任务。

### 配置说明

OpenCode server 配置位于 `.devcontainer/opencode.jsonc`：
- 端口：`4096`
- 模型：`opencode/big-pickle`
- 权限模式：`allow`（自动允许所有操作）

## 3. 目录结构

```
/workspaces/ai-codebox/
├── .devcontainer/           # 开发容器配置
│   ├── devcontainer.json    # Codespace 配置（端口转发、服务启动）
│   ├── Dockerfile           # 容器镜像定义
│   ├── flake.nix            # Nix 包管理配置
│   └── opencode.jsonc       # OpenCode server 配置
├── index.html               # 静态首页（用于展示结果）
├── README.md                # 项目说明
└── AGENTS.md                # 本文件 — AI Agent 使用指南
```

## 4. 使用 codebox.py 连接到此代码空间

`codebox.py` 是 Hermes Agent 或其他 AI Agent 用来连接 Codebox（此代码空间）的客户端脚本。你可以通过以下方式使用它：

### 基本用法

```python
from codebox import Codebox

# 连接到代码空间
cb = Codebox(url="http://<codespace-url>:4096")

# 执行指令
result = cb.run("ls -la")
print(result)

# 读取文件
content = cb.read("/workspaces/ai-codebox/README.md")

# 写入文件
cb.write("/workspaces/ai-codebox/output.md", "任务完成报告")
```

### 环境变量配置

建议将代码空间 URL 配置为环境变量：

```bash
export CODEBOX_URL="http://<codespace-url>:4096"
```

然后在脚本中读取：

```python
import os
from codebox import Codebox

cb = Codebox(url=os.environ["CODEBOX_URL"])
```

### 工作流程

1. Agent 通过 `codebox.py` 连接到此代码空间
2. 执行代码编写、调试、测试等任务
3. 将生成的页面（如 `index.html`）通过代码空间的公开 URL 分享
4. 通过 Telegram 等渠道将结果链接发送给用户
