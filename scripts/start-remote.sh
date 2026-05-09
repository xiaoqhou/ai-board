#!/usr/bin/env bash
# start-remote.sh - Start opencode server + cloudflared tunnel (for remote access)
set -euo pipefail

WORKSPACE="/workspaces/ai-board"
LOG_DIR="/tmp"
SERVER_PORT=8080
TUNNEL_LOG="$LOG_DIR/cloudflared.log"
TUNNEL_URL_FILE="$LOG_DIR/tunnel-url"

echo "[start-remote] Starting remote environment for $WORKSPACE..."

# Install opencode if not present
if ! command -v opencode &>/dev/null; then
    echo "[start-remote] Installing opencode from nixpkgs..."
    nix-env -iA nixpkgs.opencode 2>/dev/null || true
fi

# Install cloudflared if not present
if ! command -v cloudflared &>/dev/null; then
    echo "[start-remote] Installing cloudflared..."
    nix-env -iA nixpkgs.cloudflared 2>/dev/null || true
fi

# Kill existing opencode server
pkill -f "opencode serve" 2>/dev/null || true
sleep 1

# Kill existing cloudflared
pkill -f cloudflared 2>/dev/null || true
rm -f "$TUNNEL_LOG"
sleep 1

# Start opencode server
echo "[start-remote] Starting opencode serve on 0.0.0.0:$SERVER_PORT..."
nohup opencode serve --hostname 0.0.0.0 --port $SERVER_PORT > "$LOG_DIR/opencode.log" 2>&1 &
echo $! > "$LOG_DIR/opencode.pid"
sleep 3

# Verify opencode is running
if ! curl -s "http://127.0.0.1:$SERVER_PORT/global/health" &>/dev/null; then
    echo "[start-remote] ERROR: opencode server failed to start"
    cat "$LOG_DIR/opencode.log"
    exit 1
fi
echo "[start-remote] opencode server ready"

# Start cloudflared tunnel
echo "[start-remote] Starting cloudflared tunnel..."
cloudflared tunnel --url "http://localhost:$SERVER_PORT" > "$TUNNEL_LOG" 2>&1 &
echo $! > "$LOG_DIR/cloudflared.pid"

# Wait for tunnel URL
TUNNEL_URL=""
for i in $(seq 1 30); do
    sleep 1
    TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | tail -1)
    [ -n "$TUNNEL_URL" ] && break
done

if [ -z "$TUNNEL_URL" ]; then
    echo "[start-remote] ERROR: tunnel URL not found after 30s"
    exit 1
fi

echo "$TUNNEL_URL" > "$TUNNEL_URL_FILE"
echo "[start-remote] Remote endpoint: $TUNNEL_URL"
echo "[start-remote] DONE"