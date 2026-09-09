#!/usr/bin/env bash
# Mac-side helpers. Source this from ~/.zshrc:
#   source ~/bin/agentbox.sh

# One-line paste to hand a fresh box. Prints the command, copies it to clipboard.
# Usage: bootstrap-cmd my-hostname
bootstrap-cmd() {
  local name="${1:-agent-box}"
  local url="https://raw.githubusercontent.com/giannisp09/herdr-tailscale-setup/main/bootstrap.sh"
  # The key is expanded into the clipboard here, not on the box, so a TSKEY
  # that is unset or half-copied on this Mac becomes a command that looks
  # perfectly fine and fails two minutes into the remote install. Catch it now.
  # A whole key is tskey-auth-<keyID>-<secret>; a double-click in the admin
  # console selects only up to the first dash and gives you the keyID alone.
  case "${TSKEY:-}" in
    tskey-auth-*-*|tskey-client-*-*) ;;
    "")
      echo "TSKEY is not set in this shell. export it first." >&2
      return 1 ;;
    tskey-api-*)
      echo "TSKEY is an API access token. Machines need an auth key." >&2
      return 1 ;;
    *)
      echo "TSKEY is not a whole auth key (want tskey-auth-<keyID>-<secret>)." >&2
      echo "Got ${#TSKEY} chars starting '${TSKEY:0:12}'." >&2
      return 1 ;;
  esac
  local id
  id="$(printf %s "$TSKEY" | cut -d- -f1-3)"
  echo "curl -fsSL $url | TSKEY='$TSKEY' bash -s $name" | pbcopy
  echo "copied to clipboard: $name, key $id-... (${#TSKEY} chars)"
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
