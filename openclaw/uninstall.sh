#!/usr/bin/env bash
# install.sh が入れたものを全部外す。--purge を付けると OpenClaw 本体(npm)と ~/.openclaw も消す。
set -uo pipefail
OC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CODEX_HOOKS="${CODEX_HOME:-$HOME/.codex}/hooks.json"

for f in "$OC_DIR"/bin/hatch-*; do
  l="$BIN/$(basename "$f")"; [ -L "$l" ] && rm -f "$l"
done
echo "removed bin links"
[ -L "$HOME/.openclaw/skills/hatch" ] && rm -f "$HOME/.openclaw/skills/hatch" && echo "removed skill link"
rm -f "$HOME/.openclaw/hatch-notify.env" "$HOME/.openclaw/hatch-notify.log" && echo "removed hatch-notify.env / .log"

strip_hooks() {
  local target="$1"
  [ -f "$target" ] && grep -qF "$OC_DIR/bin/hatch-notify" "$target" || return 0
  cp "$target" "$target.bak-$(date +%Y%m%d%H%M%S)"
  jq --arg needle "$OC_DIR/bin/hatch-notify" '
    .hooks |= with_entries(
      .value |= map(select(((.hooks // []) | map(.command // "") | join("\n")) | contains($needle) | not))
    ) | .hooks |= with_entries(select(.value | length > 0))' "$target" >"$target.tmp" && mv -f "$target.tmp" "$target"
  echo "removed hatch-notify hooks from $target (backup kept)"
}
strip_hooks "$CLAUDE_SETTINGS"
strip_hooks "$CODEX_HOOKS"

if command -v openclaw >/dev/null 2>&1; then
  openclaw config patch --stdin >/dev/null 2>&1 <<<'{ hooks: null, tools: { exec: { pathPrepend: null } } }' && echo "disabled OpenClaw hooks"
fi
if [ "${1:-}" = --purge ]; then
  openclaw gateway stop >/dev/null 2>&1; openclaw gateway uninstall >/dev/null 2>&1
  npm uninstall -g openclaw && rm -rf "$HOME/.openclaw" && echo "purged OpenClaw (npm + ~/.openclaw)"
else
  echo "OpenClaw 本体はそのまま。全部消すなら: $0 --purge"
fi
