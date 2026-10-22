#!/usr/bin/env bash
# 全エージェントセッションの一覧 popup。選ぶと起動元ウィンドウへ移動して popup で再接続する。
# 判定は tmux のセッション名の接頭辞(@hatch_list_prefixes)。Claude Code / Codex の内部ファイルには依存しない。
# Args: [client_name]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../vendor/tmux-claude-hatch/scripts/helpers.sh"

claude_prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
codex_prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
prefixes="$(get_tmux_option @hatch_list_prefixes "$claude_prefix $codex_prefix")"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"
me="${1:-}"

# popup の中から呼ばれた場合はまず閉じる(popup 上に popup を重ねると入力が届かない)
my_session="$(tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null | awk -v me="$me" '$1 == me { print $2; exit }')"
for p in $prefixes; do
  case "$my_session" in
  "$p"*)
    tmux detach-client -s "$my_session"
    sleep 0.2
    break
    ;;
  esac
done

out="$(mktemp -t hatch-agents.XXXXXX)"
trap 'rm -f "$out"' EXIT

tmux display-popup -b rounded -T " Agents " -w "$w" -h "$h" -E \
  "$DIR/pick-agents.sh '$prefixes' > '$out'"

session="$(cat "$out")"
[ -n "$session" ] || exit 0

# 起動元ウィンドウ: 自前(@hatch_origin)と上流(@claude_origin)の両方を見る
origin="$(tmux show-option -t "$session" -qv @hatch_origin 2>/dev/null)"
[ -n "$origin" ] || origin="$(tmux show-option -t "$session" -qv @claude_origin 2>/dev/null)"
[ -n "$origin" ] && tmux select-window -t "$origin" 2>/dev/null

case "$session" in
"$codex_prefix"*) title=" Codex " ;;
*) title=" Agent " ;;
esac
tmux display-popup -w "$w" -h "$h" -b rounded -T "$title" -E "tmux attach-session -t '$session'"
