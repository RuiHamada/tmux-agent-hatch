#!/usr/bin/env bash
# Wire tmux-agent-hatch into ~/.tmux.conf, ~/.codex/hooks.json and
# ~/.claude/settings.json. Idempotent: every step is skipped when already done.
#
#   install.sh            do everything
#   install.sh --tmux     only the tmux side
#   install.sh --codex    only the Codex hooks
#   install.sh --claude   only the Claude Code hooks
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF="${TMUX_CONF:-$HOME/.tmux.conf}"
CODEX_HOOKS="${CODEX_HOME:-$HOME/.codex}/hooks.json"
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

for t in tmux fzf jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing: $t" >&2; exit 1; }
done

backup() { cp "$1" "$1.bak-$(date +%Y%m%d%H%M%S)"; }

# render_hooks <template>: the template with __HATCH_DIR__ filled in.
render_hooks() { sed "s|__HATCH_DIR__|$DIR|g" "$1"; }

# merge_hooks <target> <template> <jq path to the hooks object>
# Creates <target> from the template, or appends our matcher groups to each
# event already there. Skips when <target> already mentions this checkout.
merge_hooks() {
  local target="$1" template="$2" path="$3" ours
  ours="$(render_hooks "$template")"
  if [ ! -f "$target" ]; then
    mkdir -p "$(dirname "$target")"
    if [ "$path" = '.hooks' ]; then
      printf '%s\n' "$ours" >"$target"
    else
      printf '%s\n' "$ours" | jq "{hooks: .hooks}" >"$target"
    fi
    echo "created $target"
  elif grep -qF "$DIR/hooks/" "$target"; then
    echo "already configured: $target"
  else
    backup "$target"
    jq --argjson ours "$(printf '%s' "$ours" | jq .hooks)" \
      "$path = (($path // {}) as \$cur | \$ours | to_entries | reduce .[] as \$e (\$cur; .[\$e.key] = ((.[\$e.key] // []) + \$e.value)))" \
      "$target" >"$target.tmp" && mv -f "$target.tmp" "$target"
    echo "merged hooks into $target (backup kept)"
  fi
}

do_tmux() {
  if ! grep -qF 'hatch.tmux.conf' "$TMUX_CONF" 2>/dev/null; then
    printf '\n# tmux-agent-hatch\nHATCH_DIR="%s"\nsource-file "$HATCH_DIR/hatch.tmux.conf"\n' "$DIR" >>"$TMUX_CONF"
    echo "appended to $TMUX_CONF"
  else
    echo "already configured: $TMUX_CONF"
  fi
  if tmux info >/dev/null 2>&1; then
    tmux source-file "$TMUX_CONF" && echo "reloaded running tmux server"
  fi
}

do_codex() {
  merge_hooks "$CODEX_HOOKS" "$DIR/hooks/codex/hooks.json" '.hooks'
  echo "Codex asks you to trust new hooks once: start codex and confirm, or run /hooks inside it."
}

do_claude() {
  merge_hooks "$CLAUDE_SETTINGS" "$DIR/hooks/claude/hooks.json" '.hooks'
}

case "${1:-all}" in
--tmux) do_tmux ;;
--codex) do_codex ;;
--claude) do_claude ;;
all | --all) do_tmux; do_codex; do_claude ;;
*) echo "usage: install.sh [--tmux|--codex|--claude]" >&2; exit 2 ;;
esac
