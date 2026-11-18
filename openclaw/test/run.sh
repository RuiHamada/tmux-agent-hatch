#!/usr/bin/env bash
# Tests for the OpenClaw bridge, with stand-in agents (no model is called).
#   openclaw/test/run.sh                       local tests
#   HATCH_TEST_HOST=<ssh-host> openclaw/test/run.sh   also the remote close test against that host
# Everything runs in throwaway tmux sessions named *-zzt-*, a temporary ledger and a temporary out directory.
set -uo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; BIN="$T/../bin"
W="$(mktemp -d "${TMPDIR:-/tmp}/hatch-test.XXXXXX")"; W="$(cd "$W" && pwd -P)"
export HATCH_LEDGER="$W/ledger.tsv" HATCH_OUT_ROOT="$W/out" HATCH_NO_REAP=1
FAKELOG="$W/fake.log"; : >"$FAKELOG"
export HATCH_CLAUDE_CMD="env HATCH_FAKE_LOG=$FAKELOG $T/fake-agent" HATCH_CODEX_CMD="env HATCH_FAKE_LOG=$FAKELOG $T/fake-agent"
REPO="$W/repo"; mkdir -p "$REPO" && git -C "$REPO" init -q && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
alive(){ tmux has-session -t "=$1" 2>/dev/null; }
field(){ sed -n "s/.*$2=\([^ ]*\).*/\1/p" <<<"$1" | head -1; }
waitfor(){ local i=0; until eval "$1"; do i=$((i+1)); [ "$i" -gt "${2:-50}" ] && return 1; sleep 0.2; done; }
cleanup() {
  for s in $(tmux list-sessions -F '#S' 2>/dev/null | grep -- '-zzt-'); do tmux kill-session -t "=$s" 2>/dev/null; done
  [ -n "${HATCH_TEST_HOST:-}" ] && ssh -n -o BatchMode=yes "$HATCH_TEST_HOST" 'for s in $(tmux list-sessions -F "#S" 2>/dev/null | grep -- "-zzt-"); do tmux kill-session -t "=$s"; done' 2>/dev/null
  [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2>/dev/null
  rm -rf "$W"
}
trap cleanup EXIT

echo "== launch: model and effort per launch"
r="$("$BIN/hatch-launch" --slug zzt-w --expect e1 --model m-one --effort high claude "$REPO" "first task")"
S="$(field "$r" session)"; OUT="$(field "$r" out)"
check "writer session created"                 'alive "$S"'
check "claude gets --model/--effort"           'waitfor "grep -q -- \"--model m-one --effort high\" \"$FAKELOG\""'
check "meta.json records model and effort"     '[ "$(jq -r ".model + \"/\" + .effort" "$OUT/meta.json")" = m-one/high ]'
check "ledger shows the model"                 '"$BIN/hatch-ledger" show "$S" | grep -q "^model=m-one/high"'
check "round 1 report written by the agent"    'waitfor "[ -f \"$OUT/report.md\" ]"'
r2="$("$BIN/hatch-launch" --readonly --slug zzt-c --model m-two --effort low codex "$REPO" "review")"
check "codex gets -m / -c model_reasoning_effort / read-only" 'waitfor "grep -q -- \"-m m-two -c model_reasoning_effort=low --sandbox read-only\" \"$FAKELOG\""'
REPO3="$W/repo3"; mkdir -p "$REPO3" && git -C "$REPO3" init -q
r3="$("$BIN/hatch-launch" --slug zzt-cw codex "$REPO3" "write")"; OUT3="$(field "$r3" out)"
check "writing codex may write its out directory (--add-dir)" 'waitfor "grep -q -- \"--add-dir $OUT3 \" \"$FAKELOG\""'
check "read-only codex gets no --add-dir"         '! grep -- "--sandbox read-only" "$FAKELOG" | grep -q -- "--add-dir"'
hl="$("$BIN/hatch-list")"
check "hatch-list columns carry round and model" 'sed -n 1p <<<"$hl" | grep -q "round.model"'

echo "== second writer is refused, with a message that fits the blocker's state"
m="$("$BIN/hatch-launch" --slug zzt-w2 claude "$REPO" "x" 2>&1)"; rc=$?
check "refused while the first writer is open (rc 3)" '[ "$rc" -eq 3 ] && grep -q "another writer session" <<<"$m" && grep -q -- "--continue $S" <<<"$m"'
"$BIN/hatch-ledger" close "$S" "verified" >/dev/null
check "close marks the writer session as closed"  '[ "$(tmux show-options -t "$S" -qv @hatch_closed)" = 1 ]'
check "writer survives its own close (grace)"     'alive "$S"'
m="$("$BIN/hatch-launch" --slug zzt-w2 claude "$REPO" "x" 2>&1)"; rc=$?
check "refusal says the blocker is closed and offers --continue / hatch-end" '[ "$rc" -eq 3 ] && grep -q "already closed" <<<"$m" && grep -q -- "--continue $S" <<<"$m" && grep -q "hatch-end $S" <<<"$m"'

echo "== --continue on a live session"
r="$("$BIN/hatch-launch" --continue "$S" --expect e2 "second round
with two lines")"
check "state=continued round=2"                'grep -q "state=continued" <<<"$r" && grep -q "round=2" <<<"$r"'
check "round 2 writes report-2.md"             'waitfor "[ -f \"$OUT/report-2.md\" ]"'
check "round 1 report kept"                    '[ -f "$OUT/report.md" ]'
check "ledger: session open again in round 2"  '[ "$("$BIN/hatch-ledger" status "$S")" = open ] && "$BIN/hatch-ledger" show "$S" | grep -q "^round=2 (of 2)"'
check "closed mark cleared"                    '[ -z "$(tmux show-options -t "$S" -qv @hatch_closed)" ]'
check "reap leaves a continued task alone"     '[ -z "$("$BIN/hatch-reap" --grace-min 0 --dry-run)" ] || ! "$BIN/hatch-reap" --grace-min 0 --dry-run | grep -q "$S"'
rp="$("$BIN/hatch-report" "$S")"; rp1="$("$BIN/hatch-report" --round 1 "$S")"   # (no `| head`: with pipefail a closed pipe reads as failure)
check "hatch-report shows the newest round"    'sed -n 1p <<<"$rp" | grep -q "/report-2.md"'
check "hatch-report --round 1 shows the first" 'sed -n 1p <<<"$rp1" | grep -q "/report.md"'
check "continue keeps the task model"          '"$BIN/hatch-ledger" show "$S" | grep -q "^model=m-one/high"'

echo "== --continue on an ended session resumes the saved conversation"
jq '.agent_session_id = "sid-123"' "$OUT/meta.json" >"$OUT/m" && mv "$OUT/m" "$OUT/meta.json"
"$BIN/hatch-ledger" close "$S" "verified 2" >/dev/null; "$BIN/hatch-end" "$S" >/dev/null
check "session ended"                          '! alive "$S"'
r="$("$BIN/hatch-launch" --continue zzt-w "third round")"
check "state=resumed round=3 (looked up by slug)" 'grep -q "state=resumed" <<<"$r" && grep -q "round=3" <<<"$r"'
check "claude started with --resume <id>"      'waitfor "grep -q -- \"--model m-one --effort high --resume sid-123\" \"$FAKELOG\""'
check "same session name, same directory"      'alive "$S" && [ "$(tmux display-message -p -t "$S" "#{session_path}")" = "$REPO" ]'
check "round 3 writes report-3.md"             'waitfor "[ -f \"$OUT/report-3.md\" ]"'
check "meta.json keeps the round history"      '[ "$(jq -r ".rounds | length" "$OUT/meta.json")" = 3 ] && [ "$(jq -r .status "$OUT/meta.json")" = running ]'

echo "== hatch-send: a long multi-line message arrives whole"
: >"$FAKELOG"
MSG="$W/msg.txt"; { echo "FIRST-LINE-MARKER line 1"; i=2; while [ $i -le 59 ]; do echo "line $i: the quick brown fox jumps over the lazy dog, again and again and again ($i)"; i=$((i+1)); done; printf 'LAST-LINE-MARKER line 60'; } >"$MSG"
"$BIN/hatch-send" "$S" "$(cat "$MSG")"
waitfor "grep -q MSG-END \"$FAKELOG\"" 60
sed -n '/^MSG-BEGIN$/,/^MSG-END$/p' "$FAKELOG" | sed '1d;$d' >"$W/got.txt"
check "all 60 lines arrived as one message"    '[ "$(grep -c "" "$W/got.txt")" -eq 60 ] && [ "$(grep -c MSG-BEGIN "$FAKELOG")" -eq 1 ]'
check "first and last lines intact"            'head -1 "$W/got.txt" | grep -q "^FIRST-LINE-MARKER line 1$" && tail -1 "$W/got.txt" | grep -q "^LAST-LINE-MARKER line 60$"'
check "content identical"                      'diff -q <(cat "$MSG"; echo) "$W/got.txt" >/dev/null'

echo "== reap: one pass handles every row"
for n in a b c; do tmux new-session -d -s "claude-zzt-ro$n" -c "$REPO" "sleep 600"; tmux set-option -t "claude-zzt-ro$n" @hatch_openclaw 1
  "$BIN/hatch-ledger" add local claude/ro "claude-zzt-ro$n" "zzt-ro$n" "$W/out/x" e >/dev/null; done
HATCH_NO_END=1 "$BIN/hatch-ledger" close claude-zzt-roa v >/dev/null; HATCH_NO_END=1 "$BIN/hatch-ledger" close claude-zzt-rob v >/dev/null; HATCH_NO_END=1 "$BIN/hatch-ledger" close claude-zzt-roc v >/dev/null
"$BIN/hatch-reap" >/dev/null 2>&1
check "three closed read-only sessions ended in one pass" '! alive claude-zzt-roa && ! alive claude-zzt-rob && ! alive claude-zzt-roc'
check "open writer in the same directory untouched"       'alive "$S"'

echo "== close ends a read-only session before returning (caller kills its process group afterwards)"
tmux new-session -d -s claude-zzt-rod -c "$REPO" "sleep 600"; tmux set-option -t claude-zzt-rod @hatch_openclaw 1
"$BIN/hatch-ledger" add local claude/ro claude-zzt-rod zzt-rod "$W/out/x" e >/dev/null
perl -e 'setpgrp(0,0); system(@ARGV); kill("TERM", -getpgrp());' "$BIN/hatch-ledger" close claude-zzt-rod verified >/dev/null 2>&1
check "session gone although the caller's group was killed" '! alive claude-zzt-rod'
check "other sessions in that directory still alive"        'alive "$S"'

if [ -n "${HATCH_TEST_HOST:-}" ]; then
  H="$HATCH_TEST_HOST"; echo "== remote ($H): close a read-only task while another session is alive in the same directory"
  rs() { ssh -n -o BatchMode=yes "$H" "PATH=\$HOME/.local/bin:\$PATH; $1" 2>/dev/null; }
  rs 'for s in claude-zzt-rro codex-zzt-rro2 claude-zzt-rw claude-zzt-rbusy; do tmux new-session -d -s $s -c ~ "sleep 600"; tmux set-option -t $s @hatch_openclaw 1; done'
  "$BIN/hatch-ledger" add "$H" claude claude-zzt-rw zzt-rw /tmp/x e >/dev/null;       HATCH_NO_END=1 "$BIN/hatch-ledger" close claude-zzt-rw v >/dev/null   # closed writer, in grace
  "$BIN/hatch-ledger" add "$H" claude claude-zzt-rbusy zzt-rbusy /tmp/x e >/dev/null                                                                      # open, same directory
  "$BIN/hatch-ledger" add "$H" claude/ro claude-zzt-rro zzt-rro /tmp/x e >/dev/null
  "$BIN/hatch-ledger" add "$H" codex/ro codex-zzt-rro2 zzt-rro2 /tmp/x e >/dev/null
  perl -e 'setpgrp(0,0); system(@ARGV); kill("TERM", -getpgrp());' "$BIN/hatch-ledger" close claude-zzt-rro verified >/dev/null 2>&1
  check "remote read-only session ended by close"          '[ "$(rs "tmux has-session -t =claude-zzt-rro 2>/dev/null && echo up || echo gone")" = gone ]'
  HATCH_NO_END=1 "$BIN/hatch-ledger" close codex-zzt-rro2 v >/dev/null; "$BIN/hatch-reap" >/dev/null 2>&1
  check "remote reap ends a closed read-only session"      '[ "$(rs "tmux has-session -t =codex-zzt-rro2 2>/dev/null && echo up || echo gone")" = gone ]'
  check "remote closed writer (grace) and open session untouched" '[ "$(rs "tmux has-session -t =claude-zzt-rw && tmux has-session -t =claude-zzt-rbusy && echo up")" = up ]'
  check "list --all reports alive=no for the ended one"    '"$BIN/hatch-ledger" list --all | awk -F"\t" "\$4 == \"claude-zzt-rro\" { print \$8 }" | grep -qx no'
fi

echo "== hatch-notify: exact attribution, and silence where nothing happened"
# A process named "claude": a copy of bash where that runs (Linux reports the executable's name), else a symlink
# (macOS kills copies of system binaries, and reports the invoked name).
cp "$(command -v bash)" "$W/claude" 2>/dev/null; "$W/claude" -c true 2>/dev/null || { rm -f "$W/claude"; ln -s "$(command -v bash)" "$W/claude"; }
BODY="$W/bodies.txt"; : >"$BODY"; NLOG="$W/notify.log"
python3 - "$BODY" "$W/port" <<'PY' &
import sys, http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        b = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        open(sys.argv[1], 'ab').write(b + b'\n'); self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
s = socketserver.TCPServer(('127.0.0.1', 0), H); open(sys.argv[2], 'w').write(str(s.server_address[1])); s.serve_forever()
PY
STUB_PID=$!; waitfor "[ -s \"$W/port\" ]"
printf 'OPENCLAW_HOOK_URL=http://127.0.0.1:%s/hooks\nOPENCLAW_HOOK_TOKEN=test\nOPENCLAW_AGENT_ID=t\nOPENCLAW_HATCH_LOG=%s\n' "$(cat "$W/port")" "$NLOG" >"$W/notify.env"
cp "$W/notify.env" "$W/notify-default.env"              # the default scope: sessions started by hatch-launch only
echo 'OPENCLAW_HATCH_SCOPE=all' >>"$W/notify.env"       # the attribution tests below use hand-made sessions
# Each pane runs a process named "claude"; it fires hooks on request: directly (its own turn) or from a child
# claude process that has no tty (what Claude Code does for compaction and headless runs).
cat >"$W/pane.sh" <<PANE
while :; do
  if [ -f "$W/trig.\$1" ]; then
    how="\$(cat "$W/trig.\$1")"; rm -f "$W/trig.\$1"
    export HATCH_NOTIFY_ENV="$W/notify.env" HATCH_NOTIFY_END_WAIT=1
    case "\$how" in
    nested:*) python3 -c 'import os,sys; os.setsid(); os.execv(sys.argv[1], ["claude","-c",sys.argv[2]])' "$W/claude" "$BIN/hatch-notify < $W/\${how#nested:}.json; sleep 1" ;;
    *) "$BIN/hatch-notify" < "$W/\$how.json" ;;
    esac
  fi
  sleep 0.2
done
PANE
for n in na nb; do tmux new-session -d -s "claude-zzt-$n" -c "$REPO" "$W/claude $W/pane.sh $n"; done
mkdir -p "$W/out/nb"; echo '{}' >"$W/out/nb/meta.json"
tmux set-option -t claude-zzt-nb @hatch_out "$W/out/nb"; tmux set-option -t claude-zzt-nb @hatch_slug zzt-nb
tmux set-option -t claude-zzt-nb @hatch_round 2; tmux set-option -t claude-zzt-nb @hatch_report report-2.md
printf '{"hook_event_name":"Stop","cwd":"%s","session_id":"real-sid","last_assistant_message":"round two answer"}' "$REPO" >"$W/stop.json"
printf '{"hook_event_name":"Stop","cwd":"%s","session_id":"child-sid","last_assistant_message":"child"}' "$REPO" >"$W/childstop.json"
printf '{"hook_event_name":"SessionEnd","cwd":"%s","session_id":"real-sid","reason":"other"}' "$REPO" >"$W/end.json"
fire() { echo "$2" >"$W/trig.$1"; waitfor "[ ! -f \"$W/trig.$1\" ]"; sleep "${3:-1.5}"; }
fire nb stop
check "two claude sessions in one directory: the notice names the right one" 'grep -q "claude claude-zzt-nb on" "$BODY" && ! grep -q "one of" "$BODY"'
check "wake carries round and report=READY"            'grep -q "slug=zzt-nb round=2 report=READY" "$BODY"'
check "final response saved as this round's report"    'grep -q "round two answer" "$W/out/nb/report-2.md"'
check "agent session id stored for resume"             '[ "$(jq -r .agent_session_id "$W/out/nb/meta.json")" = real-sid ]'
n0="$(grep -c "" "$BODY")"; fire nb nested:childstop 3
check "hook from a child claude process: no notice"    '[ "$(grep -c "" "$BODY")" -eq "$n0" ] && grep -q "skip reason=nested-agent .*session=claude-zzt-nb" "$NLOG"'
check "child process did not replace the resume id"    '[ "$(jq -r .agent_session_id "$W/out/nb/meta.json")" = real-sid ]'
fire nb end 3
check "SessionEnd while the agent is still running: no notice" '[ "$(grep -c "" "$BODY")" -eq "$n0" ] && grep -q "skip reason=session-still-alive" "$NLOG"'
tmux set-option -t claude-zzt-na @hatch_closed 1; fire na stop
check "closed task: no notice"                         '[ "$(grep -c "" "$BODY")" -eq "$n0" ] && grep -q "skip reason=closed session=claude-zzt-na" "$NLOG"'

echo "== hatch-notify: agent that changed directory, and agents that are in no tmux session"
# Hooks fired from outside every pane, without TMUX_PANE: a daemonized process with no agent above it (as Codex's
# app-server runs them), and a process named claude on a pty that is no tmux pane (a Claude Code background session).
REPO2="$W/repo2"; mkdir -p "$REPO2/pkg/deep" "$REPO2/other/deep" "$REPO/sub" "$W/plain/sub" "$W/reg"
git -C "$REPO2" init -q
tmux new-session -d -s claude-zzt-nc -c "$REPO2" "$W/claude $W/pane.sh nc"
tmux new-session -d -s claude-zzt-nd -c "$REPO2/pkg" "$W/claude $W/pane.sh nd"
tmux new-session -d -s claude-zzt-ne -c "$W/plain" "$W/claude $W/pane.sh ne"
waitfor '[ "$(tmux display-message -p -t claude-zzt-nd "#{pane_current_path}")" = "$REPO2/pkg" ]'
stopjson() { printf '{"hook_event_name":"%s","cwd":"%s","session_id":"x","last_assistant_message":"m"}' "${2:-Stop}" "$1"; }
detached() {   # <cwd> [event]: no agent in the parent chain, no tty, no TMUX_PANE
  stopjson "$@" >"$W/d.json"
  env -u TMUX_PANE -u TMUX HATCH_NOTIFY_ENV="${HATCH_NOTIFY_ENV:-$W/notify.env}" python3 -c '
import os, sys, time
if os.fork(): os._exit(0)
os.setsid()
if os.fork(): os._exit(0)
time.sleep(0.3)
os.dup2(os.open(sys.argv[2], os.O_RDONLY), 0)
os.execv(sys.argv[1], [sys.argv[1]])' "$BIN/hatch-notify" "$W/d.json"
  sleep 2
}
last() { tail -n 1 "$BODY"; }
n0="$(grep -c "" "$BODY")"; detached "$REPO2/other/deep"
check "cwd in a subdirectory, empty TMUX_PANE: attributed to the session" '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && last | grep -q "claude claude-zzt-nc on" && grep -q "session=claude-zzt-nc by=cwd-ancestor .*tmux_pane=\$" "$NLOG"'
detached "$REPO2/pkg/deep"
check "one session directory inside another: the nearest wins" 'last | grep -q "claude claude-zzt-nd on"'
detached "$REPO2"
check "exact directory still resolves to its own session"       'last | grep -q "claude claude-zzt-nc on"'
detached "$REPO/sub"
check "two sessions at the same depth: listed, not guessed"     'last | grep -q "one of \[claude-zzt-n[ab],claude-zzt-n[ab]\]"'
n0="$(grep -c "" "$BODY")"; detached "$W/plain/sub"
check "ancestor outside a git work tree is not a match; the wake says not identified" '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && last | grep -q "(session not identified) on .*cwd=$W/plain/sub" && ! last | grep -q zzt-ne && grep -q "unattributed reason=no-pane" "$NLOG"'
n0="$(grep -c "" "$BODY")"; detached "$W/plain/sub" SessionEnd
check "SessionEnd that matches no session: logged, no notice"   '[ "$(grep -c "" "$BODY")" -eq "$n0" ] && grep -q "skip reason=no-pane event=SessionEnd" "$NLOG"'
offtmux() {   # <cwd>: a claude process on its own pty (no pane), registered as a background session
  stopjson "$1" >"$W/o.json"
  env -u TMUX_PANE -u TMUX HATCH_NOTIFY_ENV="${HATCH_NOTIFY_ENV:-$W/notify.env}" HATCH_CLAUDE_SESSIONS="$W/reg" python3 -c '
import os, pty, sys
pid, fd = pty.fork()
if pid == 0: os.execv(sys.argv[1], ["claude", "-c", sys.argv[2]])
try:
    while os.read(fd, 4096): pass
except OSError: pass
os.waitpid(pid, 0)' "$W/claude" "printf '{\"kind\":\"bg\",\"name\":\"bg job\"}' >$W/reg/\$\$.json; $BIN/hatch-notify <$W/o.json; sleep 0.5"
  sleep 2
}
n0="$(grep -c "" "$BODY")"; offtmux "$REPO2/other"
check "background claude (own pty, no pane): not handed to the session in that directory" '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && ! last | grep -q "zzt-nc"'
check "its wake names it and the cwd"                           'last | grep -q "claude background session ..bg job.. (pid [0-9]*, not in a tmux session) on .*turn finished.*cwd=$REPO2/other\." && grep -q "unattributed reason=not-in-tmux" "$NLOG"'

echo "== hatch-notify: only launched sessions by default; waiting notices say what is asked"
n0="$(grep -c "" "$BODY")"; HATCH_NOTIFY_ENV="$W/notify-default.env" detached "$REPO2"
check "session not started by hatch-launch: no notice (default scope)" '[ "$(grep -c "" "$BODY")" -eq "$n0" ] && grep -q "skip reason=not-launched .*session=claude-zzt-nc" "$NLOG"'
HATCH_NOTIFY_ENV="$W/notify-default.env" offtmux "$REPO2/other"
check "agent outside tmux: no notice (default scope)"           '[ "$(grep -c "" "$BODY")" -eq "$n0" ]'
mkdir -p "$W/out/nd"; echo '{}' >"$W/out/nd/meta.json"
tmux set-option -t claude-zzt-nd @hatch_openclaw 1; tmux set-option -t claude-zzt-nd @hatch_out "$W/out/nd"; tmux set-option -t claude-zzt-nd @hatch_slug zzt-nd
HATCH_NOTIFY_ENV="$W/notify-default.env" detached "$REPO2/pkg"
check "launched session: notified"                              '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && last | grep -q "claude-zzt-nd on"'
ask() {   # permission request with a 12-line command, fired like detached()
  jq -cn --arg c "$REPO2/pkg" --arg cmd "$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "cmd-line-$i"; done)" \
    '{hook_event_name:"PermissionRequest", cwd:$c, session_id:"x", tool_name:"shell", tool_input:{command:$cmd, description:"needs to write outside the workspace"}}' >"$W/d.json"
  env -u TMUX_PANE -u TMUX HATCH_NOTIFY_ENV="$W/notify-default.env" python3 -c '
import os, sys, time
if os.fork(): os._exit(0)
os.setsid()
if os.fork(): os._exit(0)
time.sleep(0.3)
os.dup2(os.open(sys.argv[2], os.O_RDONLY), 0)
os.execv(sys.argv[1], [sys.argv[1]])' "$BIN/hatch-notify" "$W/d.json"; sleep 2
}
n0="$(grep -c "" "$BODY")"; ask
check "permission notice carries the reason and the command"    '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && last | grep -q "waiting: permission prompt" && last | grep -q "Reason: needs to write outside the workspace" && last | grep -q "shell: cmd-line-1"'
check "long command: shortened, full text saved next to the report" 'last | grep -q "full text: $W/out/nd/ask-" && ! last | grep -q "cmd-line-12" && grep -q "cmd-line-12" "$W"/out/nd/ask-*.txt'
check "waiting notice does not ask for a report"                '! last | grep -q "report=" && last | grep -q "slug=zzt-nd (work in progress"'
ask
check "the same waiting notice again: not repeated"             '[ "$(grep -c "" "$BODY")" -eq $((n0+1)) ] && grep -q "skip reason=duplicate .*session=claude-zzt-nd" "$NLOG"'

echo; echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
