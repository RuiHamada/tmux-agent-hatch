#!/usr/bin/env bash
# Run from the Mac: make agents on an ssh host (workstation) reachable from OpenClaw.
#   remote-setup.sh <ssh-host> [tunnel-port]
# 1. git pull tmux-agent-hatch on the host and run openclaw/install.sh --remote (bin symlinks and hooks)
# 2. send the Mac's ~/.openclaw/hatch-notify.env to the host with the URL pointed at the reverse-tunnel port
# 3. print the forwards to add to the usual connection command
set -euo pipefail
host="${1:-}"; port="${2:-18790}"
[ -n "$host" ] || { echo "usage: remote-setup.sh <ssh-host> [tunnel-port]" >&2; exit 2; }
ENV_FILE="$HOME/.openclaw/hatch-notify.env"
[ -r "$ENV_FILE" ] || { echo "run install.sh first to create $ENV_FILE" >&2; exit 1; }

remote_dir="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'readlink -f ~/.config/tmux-agent-hatch 2>/dev/null || echo ~/repos/tmux-agent-hatch')"
echo "remote hatch: $host:$remote_dir"
ssh "$host" "git -C '$remote_dir' pull -q --ff-only && bash '$remote_dir/openclaw/install.sh' --remote"

ssh "$host" 'mkdir -p ~/.openclaw && chmod 700 ~/.openclaw'
{ sed -e "s|^OPENCLAW_HOOK_URL=.*|OPENCLAW_HOOK_URL=http://127.0.0.1:$port/hooks|" -e '/^OPENCLAW_HATCH_HOST=/d' "$ENV_FILE"
  echo "OPENCLAW_HATCH_HOST=\"--host $host\""; } | ssh "$host" 'umask 077; cat > ~/.openclaw/hatch-notify.env'
echo "sent hatch-notify.env (URL -> 127.0.0.1:$port via RemoteForward)"

cat <<MSG
Notification path: add these forwards to the usual connection command (active while connected)
  gcloud workstations ssh ... -- -L 2222:127.0.0.1:22 -R $port:127.0.0.1:18789
MSG
