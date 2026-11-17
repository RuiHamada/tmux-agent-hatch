#!/usr/bin/env bash
# Mac から実行: ssh 先(workstation)のエージェントも OpenClaw から扱えるようにする。
#   remote-setup.sh <ssh-host> [tunnel-port]
# 1. ssh 先の tmux-agent-hatch を git pull し、openclaw/install.sh --remote(bin の symlink と hook)
# 2. Mac の ~/.openclaw/hatch-notify.env を、URL だけ逆方向トンネルのポートに変えて ssh 先へ送る
# 3. ~/.ssh/config の Host <ssh-host> に RemoteForward が無ければ案内を出す
set -euo pipefail
host="${1:-}"; port="${2:-18790}"
[ -n "$host" ] || { echo "usage: remote-setup.sh <ssh-host> [tunnel-port]" >&2; exit 2; }
ENV_FILE="$HOME/.openclaw/hatch-notify.env"
[ -r "$ENV_FILE" ] || { echo "先に install.sh を実行して $ENV_FILE を作る" >&2; exit 1; }

remote_dir="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" 'readlink -f ~/.config/tmux-agent-hatch 2>/dev/null || echo ~/repos/tmux-agent-hatch')"
echo "remote hatch: $host:$remote_dir"
ssh "$host" "git -C '$remote_dir' pull -q --ff-only && bash '$remote_dir/openclaw/install.sh' --remote"

ssh "$host" 'mkdir -p ~/.openclaw && chmod 700 ~/.openclaw'
{ sed -e "s|^OPENCLAW_HOOK_URL=.*|OPENCLAW_HOOK_URL=http://127.0.0.1:$port/hooks|" -e '/^OPENCLAW_HATCH_HOST=/d' "$ENV_FILE"
  echo "OPENCLAW_HATCH_HOST=--host $host"; } | ssh "$host" 'umask 077; cat > ~/.openclaw/hatch-notify.env'
echo "sent hatch-notify.env (URL -> 127.0.0.1:$port via RemoteForward)"

cat <<MSG
通知の経路: 普段の接続コマンドに次を付ける(接続中だけ有効)
  gcloud workstations ssh ... -- -L 2222:127.0.0.1:22 -R $port:127.0.0.1:18789
MSG
