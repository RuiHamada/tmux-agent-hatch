#!/usr/bin/env bash
# tmux-agent-hatch (modified from tmux-claude-hatch's claude_hatch.tmux)
#
# Launch Claude Code / Codex sessions in popups and pick between them. tpm (or
# hatch.tmux.conf) runs this file as an executable on tmux startup; it reads
# user options (with sensible defaults) and installs the key bindings.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

claude_key="$(get_tmux_option @claude_launch_key 'y')"
codex_key="$(get_tmux_option @codex_launch_key 'Y')"
list_key="$(get_tmux_option @hatch_list_key 'u')"

# Launch (or re-attach to) an agent session for the current pane's directory.
# #{pane_current_path} / #{window_id} are expanded by run-shell before the args
# reach the script.
tmux bind-key "$claude_key" \
  run-shell "$CURRENT_DIR/launch.sh claude '#{q:pane_current_path}' '#{q:window_id}'"
tmux bind-key "$codex_key" \
  run-shell "$CURRENT_DIR/launch.sh codex '#{q:pane_current_path}' '#{q:window_id}'"

# Open the session picker. When pressed from inside a session popup, list.sh
# closes that popup first so the picker opens full-size on the outer client.
tmux bind-key "$list_key" \
  run-shell "$CURRENT_DIR/list.sh '#{q:client_name}'"

# Forward a bell from a dedicated session to its origin window's pane, so
# tmux's own bell machinery (window-status-bell-style, and terminal
# passthrough when that window is visible) picks it up even though the
# session that rang is a separate session from the origin.
if [ "$(get_tmux_option @claude_forward_bell 'on')" = 'on' ]; then
  tmux set-hook -g alert-bell \
    "run-shell -b \"$CURRENT_DIR/bell.sh '#{q:hook_session_name}'\""
fi
