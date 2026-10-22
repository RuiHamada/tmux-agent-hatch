#!/usr/bin/env bash
# Pull changes from craftzdog/tmux-claude-hatch into this repo's modified copy.
#
# scripts/UPSTREAM records the upstream commit the copy was last synced to. This
# fetches upstream, takes the diff from that commit to upstream's default branch,
# rewrites paths to this repo's layout and applies it as a 3-way patch. Hunks
# that collide with local modifications are left as conflict markers for you to
# resolve; afterwards update scripts/UPSTREAM (done for you when the patch
# applies cleanly).
#
#   tools/upstream-sync.sh            apply
#   tools/upstream-sync.sh --dry-run  show the patch only
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL='https://github.com/craftzdog/tmux-claude-hatch'
cd "$ROOT"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch -q upstream

old="$(sed -nE 's/.* at ([0-9a-f]{7,40}) .*/\1/p' scripts/UPSTREAM | head -1)"
[ -n "$old" ] || { echo "cannot read the synced commit from scripts/UPSTREAM" >&2; exit 1; }
new="$(git rev-parse upstream/HEAD 2>/dev/null || git rev-parse upstream/main)"

if [ "$old" = "$new" ]; then
  echo "already at upstream $new"
  exit 0
fi

# Upstream layout -> ours:
#   claude_hatch.tmux                    -> scripts/hatch.tmux
#   plugins/tmux-claude-hatch/hooks/*    -> hooks/*  (hooks.json -> hooks/claude/hooks.json)
#   scripts/*                            -> scripts/*
patch="$(git diff "$old" "$new" -- scripts claude_hatch.tmux plugins/tmux-claude-hatch/hooks |
  sed -E \
    -e 's#(a|b)/claude_hatch\.tmux#\1/scripts/hatch.tmux#g' \
    -e 's#(a|b)/plugins/tmux-claude-hatch/hooks/hooks\.json#\1/hooks/claude/hooks.json#g' \
    -e 's#(a|b)/plugins/tmux-claude-hatch/hooks/#\1/hooks/#g')"

if [ "${1:-}" = '--dry-run' ]; then
  printf '%s\n' "$patch"
  exit 0
fi

[ -n "$patch" ] || { echo "no changes under tracked paths between $old and $new"; }
if [ -n "$patch" ]; then
  if printf '%s\n' "$patch" | git apply -3 --index; then
    echo "applied upstream $old..$new cleanly"
  else
    echo "applied with conflicts: resolve the markers, then run:" >&2
    echo "  git add -A && printf 'Vendored from $UPSTREAM_URL at $new (MIT, (c) Takuya Matsuyama). Modified in this repository.\\n' > scripts/UPSTREAM" >&2
    exit 1
  fi
fi

printf 'Vendored from %s at %s (MIT, (c) Takuya Matsuyama). Modified in this repository.\n' "$UPSTREAM_URL" "$new" >scripts/UPSTREAM
git add scripts/UPSTREAM
echo "scripts/UPSTREAM now points at $new; review with: git diff --cached"
echo "Also eyeball upstream's README diff: git diff $old $new -- README.md"
