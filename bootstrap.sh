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

# Check the key before spending two minutes on installs. Tailscale's prefix
# tells you what a key is: tskey-auth- is an auth key and tskey-client- is an
# OAuth client secret (both work here), tskey-api- is an API access token and
# does not. https://tailscale.com/docs/reference/key-prefixes
case "$TSKEY" in
  tskey-auth-*|tskey-client-*) ;;
  tskey-api-*)
    echo "TSKEY is an API access token (tskey-api-...), not an auth key." >&2
    echo "Generate an auth key at https://login.tailscale.com/admin/settings/keys" >&2
    echo "-> Generate auth key -> tick Reusable. It starts with tskey-auth-." >&2
    exit 1 ;;
  *)
    echo "TSKEY does not look like a Tailscale auth key." >&2
    echo "Expected it to start with tskey-auth- (or tskey-client-)." >&2
    echo "Got ${#TSKEY} chars starting '$(printf %.12s "$TSKEY")'." >&2
    exit 1 ;;
esac

if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | $SUDO sh
fi

# The question is whether tailscaled is reachable, not whether /dev/net/tun
# exists. Containers (Docker, Vast.ai, RunPod) enable the systemd unit at
# install time and then never start it, because systemd is not PID 1.
daemon_ready() {
  local out
  out="$($SUDO tailscale status 2>&1 || true)"
  case "$out" in *"failed to connect to local"*) return 1 ;; esac
  return 0
}

if ! daemon_ready && [ -d /run/systemd/system ] && command -v systemctl >/dev/null; then
  $SUDO systemctl enable --now tailscaled || true
fi

if ! daemon_ready; then
  # No init system. Run it ourselves in userspace networking, which needs
  # neither NET_ADMIN nor /dev/net/tun.
  $SUDO mkdir -p /var/lib/tailscale /var/run/tailscale
  $SUDO sh -c 'nohup tailscaled --tun=userspace-networking \
    --state=/var/lib/tailscale/tailscaled.state \
    --socks5-server=localhost:1055 >/var/log/tailscaled.log 2>&1 &'
  for _ in $(seq 30); do daemon_ready && break; sleep 1; done
fi

daemon_ready || {
  echo "tailscaled is not responding. Check /var/log/tailscaled.log" >&2
  exit 1
}

# --reset is what makes this re-runnable. Without it a second run dies with
# "changing settings via 'tailscale up' requires mentioning all non-default
# flags", because the first run persisted --ssh and --hostname even if its
# login failed. https://tailscale.com/kb/1241/tailscale-up
if ! $SUDO tailscale up --reset --authkey="$TSKEY" --ssh --hostname="$HOST_NAME"; then
  # A node key left in tailscaled.state by a machine that was since deleted in
  # the admin console makes registration fail even with a brand new auth key.
  # https://github.com/tailscale/tailscale/issues/9382
  echo "retrying after logout to clear any stale node identity" >&2
  $SUDO tailscale logout || true
  $SUDO tailscale up --reset --authkey="$TSKEY" --ssh --hostname="$HOST_NAME"
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
