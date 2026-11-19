longslug="$(printf '%039d' 0 | tr 0 a)-bc"
r3="$("$BIN/hatch-launch" --readonly --slug "$longslug" claude "$REPO" name)"
check "legacy truncation preserves main's trailing hyphen" '[ "$(field "$r3" slug)" = "${longslug:0:40}" ] && [ "$(field "$r3" session)" = "claude-${longslug:0:40}" ]'
for i in 1 2; do r3="$("$BIN/hatch-launch" --readonly --slug zzt-common claude "$REPO" legacy)"; done
"$BIN/hatch-ledger" close zzt-common >/dev/null
check "shared legacy slug closes both rows and ends only the latest pane" 'alive claude-zzt-common && ! alive claude-zzt-common-2 && [ "$("$BIN/hatch-ledger" status claude-zzt-common)" = closed ] && [ "$("$BIN/hatch-ledger" status claude-zzt-common-2)" = closed ]'
r3="$("$BIN/hatch-launch" --readonly --slug zzt-continue-meta claude "$REPO" legacy)"
o3="$(field "$r3" out)"; s3="$(field "$r3" session)"
mkdir "$o3/meta.json.lock"
r3="$("$BIN/hatch-launch" --continue "$s3" legacy-meta-sentinel 2>/dev/null)"
check "legacy continuation records delivered round despite unwritable metadata" '[ "$(field "$r3" round)" = 2 ] && [ "$("$BIN/hatch-ledger" lookup "$s3" | cut -f6)" = 2 ] && waitfor "grep -qx legacy-meta-sentinel \"$FAKELOG\""'

if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  # Archived main's host parser and command run entirely inside the loopback fixture.
  mkdir -p "$W/main-agent/openclaw/bin" "$W/main-agent/scripts"
  for f in openclaw/bin/hatch-launch openclaw/bin/_remote.sh scripts/helpers.sh; do
    git -C "$T" show "1d0b94a:$f" >"$W/main-agent/$f" || exit 1
  done
  chmod +x "$W/main-agent/openclaw/bin/hatch-launch"
  "$BIN/hatch-ledger" add "$HATCH_TEST_HOST" codex codex-zzt-other-review zzt-other-review "$W/remote-out/history" history 1 - review old
  ln -s "$W/main-agent/openclaw/bin/hatch-launch" "$W/remote-bin/hatch-launch"
  r3="$("$BIN/hatch-launch" --host "$HATCH_TEST_HOST" --readonly --slug zzt-old-host claude "$REPO" legacy 2>/dev/null)"
  rm "$W/remote-bin/hatch-launch"
  check "unrelated legacy launch still works on an archived main host" '[ "$(field "$r3" session)" = claude-zzt-old-host ]'
fi
mkdir "$W/physical-wts"; ln -s "$W/physical-wts" "$W/link-wts"
tmux set-option -g @hatch_worktree_dir "$W/link-wts"
args=(--role review --branch r3-branch --repo zzt-symlink --task checkout codex "$REPO")
r3="$("$BIN/hatch-launch" "${args[@]}" first)"; o3="$(field "$r3" out)"
# Existing metadata can hold the lexical path even after new launches store pwd -P.
jq --arg p "$W/link-wts/r3-branch" '.cwd=$p' "$o3/meta.json" >"$o3/legacy-cwd" && mv "$o3/legacy-cwd" "$o3/meta.json"
r3="$("$BIN/hatch-launch" "${args[@]}" second 2>/dev/null)"
check "matching branch through a symlinked worktree root continues" '[ "$(field "$r3" round)" = 2 ] && [ "$(git -C "$W/physical-wts/r3-branch" branch --show-current)" = r3-branch ]'
tmux set-option -gu @hatch_worktree_dir

# Force a module failure in an isolated install home. Old installers proceed to link bin.
mkdir -p "$W/install-bin" "$W/install-home"
printf '#!/bin/sh\nexit 1\n' >"$W/install-bin/perl"; chmod +x "$W/install-bin/perl"
HOME="$W/install-home" CLAUDE_CONFIG_DIR="$W/install-home/claude" CODEX_HOME="$W/install-home/codex" PATH="$W/install-bin:$PATH" /bin/bash "$T/../install.sh" --remote >"$W/install-log" 2>&1; install_rc=$?
check "installer refuses missing Perl modules before linking commands" '[ "$install_rc" != 0 ] && grep -qi perl "$W/install-log" && [ ! -e "$W/install-home/.local/bin" ]'
"$BIN/hatch-ledger" add local codex zzt-dual-key earlier "$W/out/dual1" legacy
"$BIN/hatch-ledger" add local codex zzt-later zzt-dual-key "$W/out/dual2" legacy
HATCH_NO_END=1 "$BIN/hatch-ledger" close zzt-dual-key >/dev/null 2>&1; dual_rc=$?
check "legacy session and slug matches retain main's close semantics" '[ "$dual_rc" = 0 ] && [ "$("$BIN/hatch-ledger" status zzt-dual-key)" = closed ] && [ "$("$BIN/hatch-ledger" status zzt-later)" = closed ]'
