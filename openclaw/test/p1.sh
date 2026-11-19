# Sourced by run.sh. Use the installed hook templates only as data.
echo "== P1: existing hooks and ordinary role turns"
p1_launch() { "$BIN/hatch-launch" --role review --repo zzt-p1 --task "$1" claude "$REPO" "$2"; }
printf 'OPENCLAW_HOOK_URL=http://127.0.0.1:1/hooks\nOPENCLAW_HOOK_TOKEN=test\nOPENCLAW_HATCH_LOG=%s\n' "$W/p1-notify.log" >"$W/p1.env"
p1_run="$(p1_launch interrupted no-stop-sentinel)"
p1_session="$(field "$p1_run" session)"; p1_out="$(field "$p1_run" out)"
# Model a live, idle CLI after an interruption that never ran Stop.
p1_pid="$(tmux display-message -p -t "$p1_session" '#{pane_pid}')"
if [ -r "/proc/$p1_pid/stat" ]; then
  p1_start="$(sed 's/.*) //' "/proc/$p1_pid/stat" | cut -d' ' -f20)"
else
  p1_start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$p1_pid" | awk '{$1=$1; print}')"
fi
p1_status() {
  jq -n --argjson pid "$p1_pid" --arg cwd "$REPO" --arg start "$p1_start" --arg status "$1" \
    '{kind:"interactive",pid:$pid,cwd:$cwd,procStart:$start,status:$status,sessionId:"p1-sid",updatedAt:1}' >"$CLAUDE_CONFIG_DIR/sessions/p1.json"
}
p1_hook() {
  local pane
  pane="$(tmux display-message -p -t "$p1_session" '#{pane_id}')"
  jq -cn --arg event "$1" --arg answer "${2:-}" '{hook_event_name:$event,session_id:"p1-sid",last_assistant_message:$answer}' |
    TMUX_PANE="$pane" HATCH_NOTIFY_ENV="$W/p1.env" "$BIN/hatch-notify"
}
rm -f "$p1_out/.stop-1" "$p1_out/report.md"
p1_status busy
HATCH_TURN_WAIT_SEC=0 p1_launch interrupted busy-sentinel >/dev/null 2>&1; p1_rc=$?
check "role refuses a new instruction while working" '[ "$p1_rc" = 3 ] && ! grep -qx busy-sentinel "$FAKELOG"'
p1_status idle
p1_hook PermissionRequest
"$BIN/hatch-send" "$p1_session" test-answer
p1_hook Stop $'Task: interrupted / Round: 1\ncompleted after answering'
check "answering via hatch-send still yields the matching report and completion notice" 'grep -q "completed after answering" "$p1_out/report.md" && waitfor "grep -q \"send-failed event=Stop session=$p1_session \" \"$W/p1-notify.log\""'
# An idle same-task operator continuation is explicit, even with no Stop or report.
rm -f "$p1_out/.stop-1" "$p1_out/report.md"
p1_run="$(HATCH_TURN_WAIT_SEC=0 "$BIN/hatch-launch" --continue "$p1_session" explicit-recovery)"
check "idle same-task continuation after no Stop advances exactly one round" '[ "$(field "$p1_run" round)" = 2 ] && [ "$(field "$p1_run" out)" = "$p1_out" ]'
p1_hook Stop $'Task: interrupted / Round: 1\nold response'
check "a stale round answer cannot become the next read-only report" '[ ! -e "$p1_out/report-2.md" ]'
p1_hook Stop $'Task: interrupted / Round: 2\nnew response'
check "the next matching answer recovers normal report capture" 'grep -q "new response" "$p1_out/report-2.md"'
check "role metadata does not leak dispatch internals into the ledger note" '! "$BIN/hatch-ledger" show "$p1_session" | grep -q "dispatch="'
check "role integration registers no per-prompt notification hook" 'jq -e ".hooks.UserPromptSubmit == null" "$T/../hooks/"{claude,codex}.json >/dev/null'
rm -f "$CLAUDE_CONFIG_DIR/sessions/p1.json"

# A newer round in the same out belongs to the current ledger, not a stale snapshot.
p1_status idle
cp "$HATCH_LEDGER" "$W/p1-old-ledger"
p1_run="$(p1_launch next next-round)"
"$BIN/hatch-ledger" close "$p1_session" >/dev/null
tmux set-option -ut "$p1_session" @hatch_closed
HATCH_LEDGER="$W/p1-old-ledger" "$BIN/hatch-ledger" close "$p1_session" >/dev/null
check "stale close cannot silence a newer role round" '[ "$(field "$p1_run" round)" = 3 ] && [ -z "$(tmux show-options -t "$p1_session" -qv @hatch_closed)" ]'
HATCH_LEDGER="$W/p1-old-ledger" "$BIN/hatch-end" "$p1_session" >/dev/null 2>&1; p1_rc=$?
check "stale closed ledger cannot end a newer role round" '[ "$p1_rc" = 3 ] && alive "$p1_session"'
rm -f "$CLAUDE_CONFIG_DIR/sessions/p1.json"

if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  p1_remote() { "$BIN/hatch-launch" --host "$HATCH_TEST_HOST" --role research --repo zzt-loss --task "$1" codex "$REPO" "$2"; }
  p1_run="$(p1_remote first start)"
  p1_session="$(field "$p1_run" session)"; p1_out="$(field "$p1_run" out)"
  p1_loss="$(HATCH_TEST_DROP_REPLY=1 p1_remote second lost-reply-sentinel 2>&1)"; p1_rc=$?
  p1_retry="$(p1_remote second lost-reply-sentinel 2>&1)"; p1_retry_rc=$?
  check "lost SSH reply reports the role and round without claiming success" '[ "$p1_rc" = 255 ] && grep -Fq "session=$p1_session task=second round=2 out=$p1_out" <<<"$p1_loss" && ! grep -q "state=continued" <<<"$p1_loss"'
  check "repeating an uncertain dispatch cannot send a second time" '[ "$p1_retry_rc" = 3 ] && [ "$("$BIN/hatch-ledger" lookup "$p1_session" "$HATCH_TEST_HOST" | cut -f6)" = 1 ] && waitfor "grep -qx lost-reply-sentinel \"$FAKELOG\"" && [ "$(grep -cx lost-reply-sentinel "$FAKELOG")" = 1 ]'
fi

# Simulate ps reporting the already registered fake processes as Codex binaries.
# The unknown-status fallback must not add a second row for any registered PID.
p1_a="$("$BIN/hatch-launch" --role review --repo zzt-status-a --task first codex "$REPO" first)"
p1_b="$("$BIN/hatch-launch" --role review --repo zzt-status-b --task first codex "$REPO" first)"
p1_a_name="$(field "$p1_a" session)"; p1_b_name="$(field "$p1_b" session)"
p1_pid_for() {
  "$T/../../scripts/agents.sh" | awk -F '\t' -v s="$1" 'index($8,s ":")==1 { print $3; exit }'
}
waitfor '[ -n "$(p1_pid_for "$p1_a_name")" ] && [ -n "$(p1_pid_for "$p1_b_name")" ]'
p1_a_pid="$(p1_pid_for "$p1_a_name")"; p1_b_pid="$(p1_pid_for "$p1_b_name")"
mkdir "$W/p1-ps"
cat >"$W/p1-ps/ps" <<'PS'
#!/bin/bash
if [ "$*" = '-axo pid=,ppid=,comm=' ]; then
  /bin/ps "$@" | awk -v a="$P1_PID_A" -v b="$P1_PID_B" '$1==a || $1==b { $3="codex" } { print }'
else
  exec /bin/ps "$@"
fi
PS
chmod +x "$W/p1-ps/ps"
waitfor '[ -f "$CODEX_HOME/hatch-status/fake-$p1_a_pid.json" ] && [ -f "$CODEX_HOME/hatch-status/fake-$p1_b_pid.json" ]'
p1_listing="$(P1_PID_A="$p1_a_pid" P1_PID_B="$p1_b_pid" PATH="$W/p1-ps:$PATH" "$BIN/hatch-list")"
check "registered Codex PIDs do not appear twice with unknown status" 'awk -F "\t" -v a="$p1_a_name" -v b="$p1_b_name" '\''($6==a || $6==b) { seen[$6]++; if ($2!="idle") bad=1 } END { exit (bad || seen[a]!=1 || seen[b]!=1) }'\'' <<<"$p1_listing"'

# Codex Escape records a turn abort without calling Stop. Keep the old hook status
# deliberately busy and verify continuation against the latest turn in the rollout.
p1_aborted="$W/aborted.jsonl"
p1_reg="$CODEX_HOME/hatch-status/fake-$p1_a_pid.json"
jq --arg path "$p1_aborted" '.status="busy" | .turnId="stopped" | .transcriptPath=$path' "$p1_reg" >"$W/abort-reg"
mv "$W/abort-reg" "$p1_reg"
p1_abort_out="$(field "$p1_a" out)"
rm "$p1_abort_out/report.md"
printf '%s\n' '{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"stopped"}}' \
  '{"type":"event_msg","payload":{"type":"task_started","turn_id":"newer"}}' >"$p1_aborted"
HATCH_TURN_WAIT_SEC=0 "$BIN/hatch-launch" --continue "$p1_a_name" must-not-send >/dev/null 2>&1; p1_rc=$?
check "an earlier abort does not release a newer working turn" '[ "$p1_rc" = 3 ] && [ "$(tmux show-options -t "$p1_a_name" -qv @hatch_round)" = 1 ]'
printf '%s\n' '{"type":"event_msg","payload":{"type":"turn_aborted","turn_id":"stopped"}}' >"$p1_aborted"
p1_resume="$(HATCH_TURN_WAIT_SEC=0 "$BIN/hatch-launch" --continue "$p1_a_name" recover-after-abort)"
check "a verified same-turn abort allows explicit recovery without Stop" '[ "$(field "$p1_resume" round)" = 2 ] && [ "$(field "$p1_resume" out)" = "$p1_abort_out" ]'
