#!/usr/bin/env bash
# Forward a bell from a dedicated agent session (modified from tmux-claude-hatch) to its origin window's pane, so
# tmux's bell machinery picks it up even though the ringing session is separate.
#
#   bell.sh <session-name>   bound to the alert-bell hook via #{hook_session_name}
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

session="${1:-}"

is_hatch_session "$session" || exit 0

origin="$(tmux show-options -qv -t "$session" @claude_origin 2>/dev/null)"
[ -n "$origin" ] || exit 0

# Skip if the origin is itself a dedicated session, to avoid a forwarding loop.
origin_session="$(tmux display-message -p -t "$origin" '#{session_name}' 2>/dev/null)"
is_hatch_session "$origin_session" && exit 0

tty="$(tmux display-message -p -t "$origin" '#{pane_tty}' 2>/dev/null)"
[ -n "$tty" ] && printf '\a' >"$tty" 2>/dev/null
exit 0
