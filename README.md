# ai-codebox

This repo is for my Hermes Agent. Hermes Agent can use it to:
- code in the codespaces.
- publish the results or reports of tasks and sends the link to me through telegram.

## Codebox

Codebox 是一个 AI Agent 编程工作台，为 AI Agent 提供云端代码开发环境。基于 OpenCode 运行在 Codespaces 上，默认工作目录为 `/workspaces/ai-codebox`。

### 连接方式

Agent 通过 `codebox.py` 连接到此代码空间（OpenCode server 运行在端口 `4096`）：

```python
from codebox import Codebox

cb = Codebox(url="http://<codespace-url>:4096")
result = cb.run("ls -la")
```

建议将代码空间 URL 配置为环境变量：

```bash
export CODEBOX_URL="http://<codespace-url>:4096"
```
