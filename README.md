# ai-codebox

This repo is for my Hermes Agent. Hermes Agent can use it to:
- Code in the codespaces
- Publish task results or reports and send the link to me through Telegram

## Codebox

Codebox is a programming workspace for AI Agents, providing a cloud-based development environment. It runs on Codespaces with OpenCode. Default working directory is `/workspaces/ai-codebox`.

### Connection Method

Agents connect to this codespace via `codebox.py` (OpenCode server runs on port `4096`):

```python
from codebox import Codebox

cb = Codebox(url="http://<codespace-url>:4096")
result = cb.run("ls -la")
```

Recommended to configure codespace URL as environment variable:

```bash
export CODEBOX_URL="http://<codespace-url>:4096"
```
