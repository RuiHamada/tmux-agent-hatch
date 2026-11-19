#!/usr/bin/env bash
# Install the OpenClaw <-> tmux-agent-hatch bridge. Safe to run repeatedly. Remove with uninstall.sh.
#   1. symlink bin/ into ~/.local/bin (so OpenClaw's exec and the hooks can call hatch-launch etc.)
#   2. symlink skill/ to ~/.openclaw/skills/hatch
#   3. add hatch-notify to the Claude Code / Codex hooks (separate entries from hatch's own hooks)
#   4. enable OpenClaw's receiver (hooks.enabled + token) and write the token and URL to ~/.openclaw/hatch-notify.env
set -euo pipefail
OC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
SKILLS="$HOME/.openclaw/skills"
ENV_FILE="$HOME/.openclaw/hatch-notify.env"
CLAUDE_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
CODEX_HOOKS="${CODEX_HOME:-$HOME/.codex}/hooks.json"
MODE="${1:-}"   # --remote: a host that only runs agents (workstation); OpenClaw itself is on the Mac
for t in tmux jq curl perl; do command -v "$t" >/dev/null 2>&1 || { echo "missing: $t" >&2; exit 1; }; done
perl -MFcntl=:flock -MTime::HiRes -e 1 || { echo "missing Perl modules: Fcntl, Time::HiRes" >&2; exit 1; }
[ "$MODE" = --remote ] || command -v openclaw >/dev/null 2>&1 || { echo "missing: openclaw" >&2; exit 1; }

# 1. bin
mkdir -p "$BIN"
for f in "$OC_DIR"/bin/hatch-*; do ln -sfn "$f" "$BIN/$(basename "$f")"; done
echo "linked bin -> $BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "note: $BIN is not in PATH" ;; esac

# 2. skill
[ "$MODE" = --remote ] || {
mkdir -p "$SKILLS"
ln -sfn "$OC_DIR/skill" "$SKILLS/hatch"
echo "linked skill -> $SKILLS/hatch"
}

# 3. hooks (per event, add only where no entry contains hatch-notify; existing entries are untouched)
merge_hooks() {
  local target="$1" template="$2" ours needle="$OC_DIR/bin/hatch-notify" missing
  ours="$(sed "s|__OC_DIR__|$OC_DIR|g" "$template" | jq .hooks)"
  if [ ! -f "$target" ]; then mkdir -p "$(dirname "$target")"; echo '{}' >"$target"; fi
  missing="$(jq -r --argjson ours "$ours" --arg needle "$needle" '
    (.hooks // {}) as $cur | $ours | keys[] |
    select((($cur[.] // []) | map((.hooks // []) | map(.command // "") | join("\n")) | join("\n") | contains($needle)) | not)' "$target" | paste -sd, -)"
  if [ -z "$missing" ]; then echo "already configured: $target"; return; fi
  cp "$target" "$target.bak-$(date +%Y%m%d%H%M%S)"
  jq --argjson ours "$ours" --arg needle "$needle" '
    .hooks = ((.hooks // {}) as $cur | $ours | to_entries | reduce .[] as $e ($cur;
      if ((.[$e.key] // []) | map((.hooks // []) | map(.command // "") | join("\n")) | join("\n") | contains($needle))
      then . else .[$e.key] = ((.[$e.key] // []) + $e.value) end))' \
    "$target" >"$target.tmp" && mv -f "$target.tmp" "$target"
  echo "merged hooks into $target: $missing (backup kept)"
}
merge_hooks "$CLAUDE_SETTINGS" "$OC_DIR/hooks/claude.json"
merge_hooks "$CODEX_HOOKS" "$OC_DIR/hooks/codex.json"

# 4. OpenClaw receiver and env
if [ "$MODE" = --remote ]; then
  [ -r "$ENV_FILE" ] && echo "env present: $ENV_FILE" || echo "note: $ENV_FILE is missing; remote-setup.sh <host> on the Mac sends it"
  echo "done (remote)."; exit 0
fi
if [ -r "$ENV_FILE" ]; then
  echo "already configured: $ENV_FILE"
else
  token="$(openssl rand -hex 24 2>/dev/null || python3 -c 'import secrets;print(secrets.token_hex(24))')"
  port="$(openclaw config get gateway.port 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
  port="${port:-18789}"
  # default agent name (chosen at onboarding; main if none)
  agent="$(openclaw agents list 2>/dev/null | sed -n 's/^- \([^ ]*\) (default).*/\1/p' | head -1)"
  agent="${agent:-main}"
  printf '{ hooks: { enabled: true, token: "%s", path: "/hooks", allowedAgentIds: ["%s"], allowRequestSessionKey: false } }\n' "$token" "$agent" |
    openclaw config patch --stdin >/dev/null
  umask 077
  cat >"$ENV_FILE" <<ENV
# settings hatch-notify uses to notify OpenClaw (removed by uninstall.sh)
OPENCLAW_HOOK_URL=http://127.0.0.1:$port/hooks
OPENCLAW_HOOK_TOKEN=$token
OPENCLAW_AGENT_ID=$agent
ENV
  echo "enabled OpenClaw hooks and wrote $ENV_FILE"
fi
# let exec find hatch-* via PATH
openclaw config patch --stdin >/dev/null <<<"{ tools: { exec: { pathPrepend: [\"$BIN\"] } } }"
echo "done. Next: openclaw onboard (model connection) -> openclaw gateway run or install -> in chat: \"use hatch to look at ~/Git/xxx\""
