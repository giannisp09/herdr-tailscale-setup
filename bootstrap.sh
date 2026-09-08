#!/usr/bin/env bash
# Provision a fresh Ubuntu box for remote agent work.
#
# Usage on the target box:
#   curl -fsSL <raw-url-of-this-file> | \
#     TSKEY=tskey-auth-xxx ANTHROPIC_API_KEY=sk-ant-xxx bash -s my-hostname
#
# Idempotent. Safe to re-run.

set -euo pipefail

HOST_NAME="${1:-agent-box}"
: "${TSKEY:?set TSKEY to a Tailscale reusable auth key}"

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

log() { printf '\n== %s\n' "$1"; }

# ---------------------------------------------------------------- PATH first
# Ubuntu's .bashrc returns early for non-interactive shells, so anything
# appended to the end never runs under `ssh host 'cmd'`. herdr's own remote
# bootstrap uses exactly that kind of shell, so this line must be at the top.
log "PATH"
if ! head -1 "$HOME/.bashrc" | grep -q '.local/bin'; then
  sed -i '1i export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------- base
log "base packages"
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq git curl ca-certificates jq rsync

# ---------------------------------------------------------------- tailscale
log "tailscale"
if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | $SUDO sh
fi

if [ -e /dev/net/tun ]; then
  $SUDO tailscale up --authkey="$TSKEY" --ssh --hostname="$HOST_NAME"
else
  # container without a TUN device
  $SUDO tailscaled --tun=userspace-networking \
    --state=/var/lib/tailscale/tailscaled.state \
    --socks5-server=localhost:1055 >/tmp/tailscaled.log 2>&1 &
  sleep 3
  $SUDO tailscale up --authkey="$TSKEY" --ssh --hostname="$HOST_NAME"
fi

# ---------------------------------------------------------------- herdr
log "herdr"
command -v herdr >/dev/null || curl -fsSL https://herdr.dev/install.sh | sh

# ---------------------------------------------------------------- node
log "node"
if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
  $SUDO apt-get install -y -qq nodejs
fi

# ---------------------------------------------------------------- claude
log "claude code"
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  grep -q ANTHROPIC_API_KEY "$HOME/.bashrc" || \
    echo "export ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY" >> "$HOME/.bashrc"
fi

# ---------------------------------------------------------------- prime cli
log "prime cli"
if ! command -v prime >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  uv tool install prime || true
fi

# ---------------------------------------------------------------- git
log "git identity"
git config --global user.name  "${GIT_NAME:-Ioannis}"
git config --global user.email "${GIT_EMAIL:-you@example.com}"
git config --global init.defaultBranch main

if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -N "" -C "$HOST_NAME" -f "$HOME/.ssh/id_ed25519"
fi

# ---------------------------------------------------------------- report
log "done"
echo "hostname : $HOST_NAME"
echo "tailnet  : $(tailscale ip -4 || echo unavailable)"
echo "herdr    : $(herdr --version 2>/dev/null || echo missing)"
echo "claude   : $(claude --version 2>/dev/null || echo missing)"
echo
echo "add this deploy key to github if this box needs to push:"
cat "$HOME/.ssh/id_ed25519.pub"
echo
echo "from your mac:  herdr --remote $HOST_NAME"
