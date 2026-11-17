# shellcheck shell=bash
# hatch-* 共通: `--host <ssh-host>`(または HATCH_HOST)が付いていたら、同じコマンドを
# その ssh ホストで実行して終わる。ホスト側にも openclaw/install.sh --remote が必要。
hatch_remote_dispatch() {
  local host="${HATCH_HOST:-}" cmd
  cmd="$(basename "$0")"
  if [ "${1:-}" = --host ]; then host="$2"; shift 2; fi
  [ -n "$host" ] || return 0
  local q=""; local a
  for a in "$@"; do q="$q $(printf '%q' "$a")"; done
  exec ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" "PATH=\$HOME/.local/bin:\$PATH $cmd$q"
}
hatch_remote_dispatch "$@"
if [ "${1:-}" = --host ]; then shift 2; fi
