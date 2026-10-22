#!/usr/bin/env bash
# Launch (or re-attach to) an agent session for a directory, shown in a popup.
# (modified from tmux-claude-hatch: takes the agent name as the first argument)
# Args: <agent: claude|codex> <dir> [origin-window-id]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

agent="${1:-claude}"
path="${2:-$PWD}"
window="${3:-}"

case "$agent" in
claude) default_cmd=claude; default_prefix=claude-; title=" Claude " ;;
codex)  default_cmd=codex;  default_prefix=codex-;  title=" Codex " ;;
*)
  tmux display-message "tmux-agent-hatch: unknown agent '$agent'"
  exit 0
  ;;
esac

prefix="$(agent_option "$agent" session_prefix "$default_prefix")"
cmd="$(agent_option "$agent" command "$default_cmd")"
args="$(agent_option "$agent" args '')"
[ -n "$args" ] && cmd="$cmd $args"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

if is_hatch_session "$(tmux display-message -p '#S')"; then
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

if ! tmux has-session -t "$session" 2>/dev/null; then
  [ -d "$path" ] || {
    tmux display-message "tmux-agent-hatch: $path no longer exists"
    exit 0
  }
  tmux new-session -d -s "$session" -c "$path" "$cmd"
fi

# Close the popup when the agent exits, even under a global detach-on-destroy off.
tmux set-option -t "$session" detach-on-destroy on

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

tmux display-popup -w "$w" -h "$h" -b rounded -T "$title" -E "tmux attach-session -t '$session'"
