#!/usr/bin/env bash
# ~/.tmux.conf に読み込み行を追記し、submodule を取得する。冪等。
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${TMUX_CONF:-$HOME/.tmux.conf}"

for t in tmux fzf jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing: $t" >&2; exit 1; }
done

git -C "$DIR" submodule update --init --quiet

if ! grep -qF 'hatch.tmux.conf' "$CONF" 2>/dev/null; then
  printf '\n# tmux-agent-hatch\nHATCH_DIR="%s"\nsource-file "$HATCH_DIR/hatch.tmux.conf"\n' "$DIR" >> "$CONF"
  echo "appended to $CONF"
else
  echo "already configured in $CONF"
fi

if tmux info >/dev/null 2>&1; then
  tmux source-file "$CONF" && echo "reloaded running tmux server"
fi

cat <<MSG

Next (optional, once): install the Claude Code plugin for bell + picker cache:
  /plugin marketplace add craftzdog/tmux-claude-hatch
  /plugin install tmux-claude-hatch@tmux-claude-hatch
MSG
