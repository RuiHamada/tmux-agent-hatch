#!/usr/bin/env bash
# Create (or reuse) a git worktree for a branch, open a window for it in the
# current session, and launch an agent popup over that window.
#
# Args: <agent: claude|codex> <branch> <dir>
#   <dir> is any directory inside the repository (the pane's current path).
#
# The worktree goes to @hatch_worktree_dir/<branch>, defaulting to a sibling of
# the repository named <repo>-wt. The new window is the place to review the
# code; the popup records it as its origin, so closing the popup and jumping
# back from the picker both land there.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

agent="${1:-codex}"
branch="${2:-}"
dir="${3:-$PWD}"

msg() { tmux display-message "tmux-agent-hatch: $*"; }

case "$agent" in
claude | codex) ;;
*) msg "unknown agent '$agent' (claude or codex)"; exit 0 ;;
esac
[ -n "$branch" ] || { msg "no branch name given"; exit 0; }
case "$branch" in
-* | *..* | *' '*) msg "bad branch name '$branch'"; exit 0 ;;
esac

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$root" ] || { msg "$dir is not inside a git repository"; exit 0; }

repo="$(basename "$root")"
base="$(get_tmux_option @hatch_worktree_dir '')"
[ -n "$base" ] || base="$(dirname "$root")/$repo-wt"
wt="$base/$branch"

if [ ! -d "$wt" ]; then
  mkdir -p "$base" 2>/dev/null
  if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
    out="$(git -C "$root" worktree add "$wt" "$branch" 2>&1)"
  else
    out="$(git -C "$root" worktree add -b "$branch" "$wt" 2>&1)"
  fi
  if [ ! -d "$wt" ]; then
    msg "git worktree add failed: ${out##*$'\n'}"
    exit 0
  fi
fi

# A window for reviewing the worktree, in the session the key was pressed in.
# Reuse one already open on this path (e.g. the key pressed twice).
window="$(tmux list-windows -F '#{window_id} #{pane_current_path}' 2>/dev/null |
  awk -v wt="$wt" '$2 == wt { print $1; exit }')"
if [ -z "$window" ]; then
  window="$(tmux new-window -n "${branch##*/}" -c "$wt" -P -F '#{window_id}' 2>/dev/null)"
fi
[ -n "$window" ] && tmux select-window -t "$window" 2>/dev/null

exec "$DIR/launch.sh" "$agent" "$wt" "$window"
