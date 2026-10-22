#!/usr/bin/env bash
# カレントディレクトリ用の Codex セッションを popup で開く(無ければ作る)。
# 上流 scripts/launch.sh と同じ構造で、コマンドと接頭辞だけ @codex_* から読む。
# Args: <dir> [origin-window-id]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../vendor/tmux-claude-hatch/scripts/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"

prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
cmd="$(get_tmux_option @codex_command 'codex')"
args="$(get_tmux_option @codex_args '')"
[ -n "$args" ] && cmd="$cmd $args"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

case "$(tmux display-message -p '#S')" in
"$prefix"* | "$(get_tmux_option @claude_session_prefix 'claude-')"*)
  tmux display-message '🫪 Popup window already open'
  exit 0
  ;;
esac

if ! tmux has-session -t "$session" 2>/dev/null; then
  [ -d "$path" ] || {
    tmux display-message "tmux-agent-hatch: $path no longer exists"
    exit 0
  }
  tmux new-session -d -s "$session" -c "$path" "$cmd"
fi

tmux set-option -t "$session" detach-on-destroy on
[ -n "$window" ] && tmux set-option -t "$session" @hatch_origin "$window"

tmux display-popup -w "$w" -h "$h" -b rounded -T " Codex " -E "tmux attach-session -t '$session'"
