#!/usr/bin/env bash
# init-env.sh - Initialize opencode server for remote agent access
set -euo pipefail

WORKSPACE="/workspaces/ai-board"

# Install opencode if not present
if ! command -v opencode &>/dev/null; then
    echo "[init-env] Installing opencode from nixpkgs..."
    nix-env -iA nixpkgs.opencode
fi

echo "[init-env] opencode version: $(opencode --version 2>/dev/null | head -1)"

# Start opencode server if not running
if ! curl -s http://localhost:8080/health &>/dev/null; then
    echo "[init-env] Starting opencode serve on 0.0.0.0:8080..."
    nohup opencode serve --hostname 0.0.0.0 --port 8080 > /tmp/opencode.log 2>&1 &
    sleep 3

    if curl -s http://localhost:8080/health &>/dev/null; then
        echo "[init-env] opencode server ready at http://localhost:8080"
    else
        echo "[init-env] WARNING: server may still be starting. Check /tmp/opencode.log"
    fi
else
    echo "[init-env] opencode server already running on port 8080"
fi

echo "[init-env] Done"