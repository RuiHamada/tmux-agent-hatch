#!/usr/bin/env bash
# Codex セッションの一覧 popup。選ぶと起動元ウィンドウへ移動して popup で再接続する。
# Codex には Claude Code のような状態ファイルが無いので、状態表示は無し(名前・パス・更新時刻のみ)。
# Args: [client_name]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../vendor/tmux-claude-hatch/scripts/helpers.sh"

prefix="$(get_tmux_option @codex_session_prefix 'codex-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"
me="${1:-}"

# popup の中から呼ばれた場合はまず閉じる(上流 list.sh と同じ理由: popup 上に popup を重ねると入力が届かない)
my_session="$(tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null | awk -v me="$me" '$1 == me { print $2; exit }')"
case "$my_session" in
"$prefix"*)
  tmux detach-client -s "$my_session"
  sleep 0.2
  ;;
esac

out="$(mktemp -t hatch-codex.XXXXXX)"
trap 'rm -f "$out"' EXIT

tmux display-popup -b rounded -T " Codex sessions " -w "$w" -h "$h" -E \
  "$DIR/pick-codex.sh '$prefix' > '$out'"

session="$(cat "$out")"
[ -n "$session" ] || exit 0

origin="$(tmux show-option -t "$session" -qv @hatch_origin 2>/dev/null)"
[ -n "$origin" ] && tmux select-window -t "$origin" 2>/dev/null
tmux display-popup -w "$w" -h "$h" -b rounded -T " Codex " -E "tmux attach-session -t '$session'"
