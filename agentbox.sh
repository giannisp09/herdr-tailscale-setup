#!/usr/bin/env bash
# Mac-side helpers. Source this from ~/.zshrc:
#   source ~/bin/agentbox.sh

# One-line paste to hand a fresh box. Prints the command, copies it to clipboard.
# Usage: bootstrap-cmd my-hostname
bootstrap-cmd() {
  local name="${1:-agent-box}"
  local url="https://raw.githubusercontent.com/giannisp09/herdr-tailscale-setup/main/bootstrap.sh"
  echo "curl -fsSL $url | TSKEY=$TSKEY bash -s $name" | pbcopy
  echo "copied to clipboard."
}

# Attach to a box's herdr session.
# Usage: box pod1
box() {
  herdr --remote "${1:-work}"
}

# Create N worktrees on a remote box so agents do not collide.
# Usage: worktrees pod1 ~/repo 3
worktrees() {
  local host="$1" repo="$2" n="${3:-3}"
  ssh "$host" "cd $repo && for i in \$(seq 1 $n); do
    git worktree add ../\$(basename $repo)-a\$i -b agent-\$i 2>/dev/null || true
  done && git worktree list"
}

# What is running and costing money right now.
podcheck() {
  prime pods list
  echo
  tailscale status
}
