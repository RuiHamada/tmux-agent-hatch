#!/usr/bin/env bash
# Codex 用キーバインドを登録する。hatch.tmux.conf の run-shell から呼ばれる。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../vendor/tmux-claude-hatch/scripts/helpers.sh"

launch_key="$(get_tmux_option @codex_launch_key 'Y')"
list_key="$(get_tmux_option @codex_list_key 'U')"

tmux bind-key "$launch_key" \
  run-shell "$DIR/launch-codex.sh '#{q:pane_current_path}' '#{q:window_id}'"
tmux bind-key "$list_key" \
  run-shell "$DIR/list-agents.sh '#{q:client_name}'"
