# AGENTS.md - AI Agent Usage Guide

Use English, stay accurate, keep it concise.

## 1. Project Overview

This project is a **programming workspace (Board) for AI Agents**, providing a cloud-based development environment for AI Agents (like Hermes Agent). Agents can write code, run commands, complete tasks, and publish results or reports through channels like Telegram.

Core components:
- **OpenCode**: Command-line based AI programming assistant, running in server mode, providing HTTP API for Agent calls.
- **Codespace**: Cloud development environment, pre-configured with Nix package manager, development tools, and OpenCode service.

## 2. AI Agent Usage (Call OpenCode via Codebox API)

OpenCode runs in server mode in this codespace (port `4096`). Agents can interact with it via HTTP API.

### API Endpoint

```
http://<codespace-url>:4096
```

### Call Format

Agents send API requests to OpenCode server with this format:

```json
{
  "messages": [
    {"role": "user", "content": "Your instructions"}
  ]
}
```

Example (using curl):

```bash
curl -X POST http://localhost:4096/api/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"List files in current directory"}]}'
```

OpenCode executes the instructions and returns results. Agents can complete complex tasks by looping API calls.

### Configuration

OpenCode server configuration is in `.devcontainer/opencode.jsonc`:
- Port: `4096`
- Model: `opencode/big-pickle`
- Permission mode: `allow` (automatically allows all operations)

## 3. Directory Structure

```
/workspaces/ai-codebox/
├── .devcontainer/           # Dev container configuration
│   ├── devcontainer.json    # Codespace configuration (port forwarding, service startup)
│   ├── Dockerfile           # Container image definition
│   ├── flake.nix            # Nix package management config
│   └── opencode.jsonc       # OpenCode server config
├── index.html               # Static homepage (for displaying results)
├── README.md                # Project documentation
└── AGENTS.md                # This file - AI Agent Usage Guide
```

## 4. Connecting to Codespace with codebox.py

`codebox.py` is a client script for Hermes Agent or other AI Agents to connect to Codebox (this codespace). Usage:

### Basic Usage

```python
from codebox import Codebox

# Connect to codespace
cb = Codebox(url="http://<codespace-url>:4096")

# Execute command
result = cb.run("ls -la")
print(result)

# Read file
content = cb.read("/workspaces/ai-codebox/README.md")

# Write file
cb.write("/workspaces/ai-codebox/output.md", "Task completion report")
```

### Environment Variable Configuration

Recommended to configure codespace URL as environment variable:

```bash
export CODEBOX_URL="http://<codespace-url>:4096"
```

Then read in script:

```python
import os
from codebox import Codebox

cb = Codebox(url=os.environ["CODEBOX_URL"])
```

### Workflow

1. Agent connects to this codespace via `codebox.py`
2. Executes coding, debugging, testing tasks
3. Shares generated pages (e.g., `index.html`) via codespace public URL
4. Sends result links to users through channels like Telegram
