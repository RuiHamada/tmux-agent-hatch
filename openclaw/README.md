# openclaw/ — use hatch agents through OpenClaw

When OpenClaw (a chat front door) starts Claude Code or Codex through its own ACP or code-agent
plugins, the agent runs as a child process without a terminal, so tmux-agent-hatch's popup, picker and
re-attach are unavailable. This directory is a thin bridge that **starts the same tmux sessions hatch
uses, from OpenClaw**, so work started in chat can be reopened from the terminal picker (prefix+u).

```
OpenClaw (chat) --exec--> hatch-launch → tmux session claude-<slug> (listed in the picker)
                <--wake--- hatch-notify ← Claude Code / Codex hooks (Stop / permission / question)
                --exec--> hatch-report / hatch-capture / hatch-send to read results and answer
```

| File | Role |
|---|---|
| `bin/hatch-launch` | One task per session (`--slug` / `--expect` / `--readonly` / `--model` / `--effort` / `--worktree`), and `--continue <session>` for follow-up rounds in the same agent conversation. Creates `~/.agents/out/<timestamp>-<slug>/`, appends a "write the report when done" instruction to the prompt, and adds a ledger row per round |
| `bin/hatch-report` | Print a task's report (latest round, or `--round N`); found through the ledger, so it works after the session ended |
| `bin/hatch-ledger` | Task ledger `~/.openclaw/hatch-ledger.tsv` (list / show / close / note; one row per round). Tracked in a file, not in OpenClaw's memory |
| `bin/hatch-end` | End a session whose ledger entry is closed (refuses open entries and sessions not started by hatch-launch; `--force` overrides) |
| `bin/hatch-reap` | Apply the ending policy to closed tasks; runs in the background from `hatch-launch` and `hatch-ledger list/close` |
| `bin/hatch-list` | The picker's data source (`scripts/agents.sh`) as TSV |
| `bin/hatch-capture` / `bin/hatch-send` | Read the screen / send text. Short answers are typed (send-keys); long or multi-line text is pasted as one buffer so it arrives whole |
| `test/run.sh` | Tests with stand-in agents (no model calls): `openclaw/test/run.sh`, or `HATCH_TEST_HOST=<ssh-host> openclaw/test/run.sh` to include the remote close test |
| `bin/hatch-notify` | Called from Claude / Codex hooks; POSTs a one-line notice to OpenClaw's `/hooks/wake`. Does nothing without `~/.openclaw/hatch-notify.env`. Logs what was sent or skipped and the HTTP status to `~/.openclaw/hatch-notify.log` (never the token or the body) |
| `hooks/claude.json`, `hooks/codex.json` | Hook templates (separate entries from hatch's own hooks) |
| `skill/SKILL.md` | The OpenClaw skill; symlinked to `~/.openclaw/skills/hatch` |
| `install.sh` / `uninstall.sh` | Install / remove (`--purge` also removes OpenClaw itself). `install.sh --remote` is for ssh hosts |
| `remote-setup.sh` | Configure an ssh host from the Mac in one go |

## Install

```sh
npm install -g openclaw@latest --allow-scripts=openclaw   # OpenClaw itself (remove with npm uninstall -g openclaw)
~/Git/tmux-agent-hatch/openclaw/install.sh                  # the bridge
openclaw onboard                                            # model connection (API keys etc., interactive)
openclaw gateway run                                        # foreground first; openclaw gateway install for a service
```

Then ask in chat (`openclaw` TUI, `openclaw dashboard`, or a connected channel), e.g. "use hatch to fix the README in ~/Git/xxx".

## Agents on an ssh host (workstation)

If hatch is installed on the workstation too, adding two forwards to the usual connection
(`gcloud workstations ssh`) lets the Mac's OpenClaw drive the workstation's agents for as long as that
connection is alive. No separate tunnel or daemon.

```sh
gcloud workstations ssh <name> ... -- -L 2222:127.0.0.1:22 -R 18790:127.0.0.1:18789
```

- `-L 2222:127.0.0.1:22`: Mac localhost:2222 → workstation sshd. `hatch-launch --host gcp-workstation ...` goes through
  `Host gcp-workstation` (localhost:2222) in `~/.ssh/config`
- `-R 18790:127.0.0.1:18789`: hook notifications on the workstation → OpenClaw on the Mac

Once, while connected, run `remote-setup.sh gcp-workstation` from the Mac (runs `openclaw/install.sh --remote` on the
workstation and sends the notification env). After that, "on the workstation, fix ~/repos/xxx" in chat becomes
`hatch-launch --host gcp-workstation ...`.

## Remove

```sh
~/Git/tmux-agent-hatch/openclaw/uninstall.sh            # bridge only (hooks, symlinks, env, OpenClaw hooks config)
~/Git/tmux-agent-hatch/openclaw/uninstall.sh --purge    # also OpenClaw itself and ~/.openclaw
```

hatch itself is touched in two small places so that both sides meet: `scripts/helpers.sh` has `worktree_path` (shared
by prefix+W and `hatch-launch --worktree`) and `delegated_session`, and `scripts/launch.sh` uses the latter so that
prefix+y / prefix+Y in a directory opens a session the bridge started there instead of starting a second agent.
Without this directory those helpers simply never match, and hatch behaves as before.

## One task per session, report.md, ledger

Countermeasures for problems seen when driving agents through chat: too many tasks piled on one session,
reports that never arrive, and reports accepted without verification.

- **One task per session**: `hatch-launch` always creates a new session `<prefix><slug>` (`-2`, `-3` on collision).
  Follow-up instructions go to an existing session only with `--reuse`. `--worktree` creates or reuses a worktree
  in the same place as hatch's prefix+W (`@hatch_worktree_dir/<branch>`, by default `<repo>-wt/<branch>` next to the
  repository; the branch is the slug, or `--branch <name>`), so a worktree made from chat and one made from the
  keyboard are the same tree.
- **Directory check**: the directory must be inside a git repository; a parent of several repositories (such as `~/Git`)
  is refused with the candidates listed. `--any-dir` launches outside a repository on purpose. This prevents
  mistakes like running a review from the parent directory.
- **Writer exclusion and read-only**: the default is a writer. If another writer is alive in the same directory,
  the launch is refused (`--worktree` / `--reuse` / `--force`). `--readonly` starts Claude with
  `--permission-mode plan` and Codex with `--sandbox read-only`; any number may share a directory. Read-only
  agents cannot write files, so hatch-notify saves the Stop hook's `last_assistant_message` (or the transcript) as
  `report.md`; this also covers writers that forgot to write one. The mode is the tmux option `@hatch_mode`
  and the `mode` column of `hatch-list`.
- **report.md**: the launch prompt gets "when done, write Summary / Changed / Validation / Handoff to
  `~/.agents/out/<timestamp>-<slug>/report.md`". The notification carries `slug=<slug> report=READY|MISSING`, and
  OpenClaw reads results with `hatch-report <session>` instead of the screen. The tmux session options
  `@hatch_out` / `@hatch_slug` tie them together.
- **Ledger**: `~/.openclaw/hatch-ledger.tsv` on the Mac. `hatch-launch` (also with `--host`) adds a row; on a
  notification OpenClaw rereads what to verify (`expect`) with `hatch-ledger show`, checks the report against it,
  and closes with `hatch-ledger close`. `hatch-ledger list` shows open tasks.

## Rounds: continuing a task (`--continue`)

Fix rounds go back to the session that did the work, so the agent keeps its design intent; reviews stay fresh
read-only sessions. `hatch-launch --continue <session|slug> [--expect "..."] "<instructions>"`:

- looks the task up in the ledger (host, agent, out directory, model and effort);
- session alive: sends the instructions to it. Session ended: starts a tmux session of the same name in the same
  directory that resumes the saved conversation (`claude --resume <id>` / `codex resume <id>`, the id that
  hatch-notify stored in `meta.json`);
- opens a new ledger row for the round (the task is open again, so the reap leaves it alone) and tells the agent to
  write `report-<N>.md`; earlier reports stay. `@hatch_round` / `@hatch_report` on the session tell hatch-notify which
  file belongs to the round, and the wake says `round=<N> report=READY`;
- keeps the one-writer rule (another writer in the directory still blocks).

`--model <name>` and `--effort <level>` are passed on the agent's own command line (`codex -m <name> -c
model_reasoning_effort=<level>`, `claude --model <name> --effort <level>`), per launch and through `--host`. The global
tmux options `@codex_args` / `@claude_args` are not involved, so overlapping launches cannot race and the user's popups
keep their settings. Both values are recorded in `meta.json`, the ledger (`hatch-ledger show`) and `hatch-list`.

## Ending sessions

One task per session leaves an idle agent behind for every delegation, so sessions end through the ledger:

| Session | Ends |
|---|---|
| read-only, ledger closed | by `hatch-ledger close` itself, before it returns (its deliverable is the report) |
| writer, ledger closed | once closed for 120 minutes (`HATCH_REAP_GRACE_MIN`, or `hatch-reap --grace-min N`) and not working or waiting |
| ledger entry open | never automatically; `hatch-end` refuses without `--force` |
| not in the ledger (your own sessions) | never |

`hatch-ledger close` ends a read-only session in the foreground: OpenClaw's exec kills the whole process group when
a command returns, so background work started by the command does not survive. `hatch-reap` covers the rest (writers past
their grace period); it is started detached, in a session of its own, by `hatch-launch` and by `hatch-ledger list/close`,
so no daemon is involved; `hatch-reap --dry-run` shows what it would do. A closed writer session carries `@hatch_closed`:
hatch-notify stays silent for it, and a launch it blocks is told to use `--continue` or `hatch-end`. Before a session is killed, `meta.json` gets
`status: "ended"`; hatch-notify has already stored the agent's own session id there (`agent_session_id`), so the conversation
can be resumed with `claude --resume <id>` / `codex resume <id>`. A session being ended sets `@hatch_ending`, and hatch-notify
stays silent for it.

## How hatch-notify finds the source pane

`TMUX_PANE` is not trusted. Codex hands the session from the TUI to an app-server daemon, and when the hook runs
under the daemon `TMUX_PANE` is whatever pane first started the daemon (possibly closed or now another session).
Tried in order:

1. Walk up the hook's parent processes to a `claude` / `codex` process and take the pane that owns its tty
2. (Codex) the `sessionId` in `~/.codex/hatch-status/<pid>.json` written by `hooks/codex/status.sh` → pid → tty → pane
3. A pane running `claude` / `codex` in the payload's `cwd`. With several candidates none is chosen; the session
   names are listed in the notification
4. `TMUX_PANE`, if it still points at an existing pane

For Claude, `TMUX_PANE` is used before the directory match when that pane still runs claude: it is inherited from the
session's own process and is exact. Three things are never notified: hooks fired by a child claude process of a session
(it has no tty of its own; Claude Code starts such processes for compaction and headless runs, and with two sessions in one
directory they used to be reported as "one of [A,B]"), sessions whose task is closed, and `SessionEnd` while the agent is
still running. `SessionEnd` is never attributed by directory: once the session's own pane is gone, a directory match can
only point at some other session working in the same place.

Targets are "claude / codex running inside a tmux pane", the same rule as `hatch-list`, not session names
(`claude-*` / `codex-*`). Agents in hand-made sessions (e.g. `graph-ws`) are notified too. When a notification
does not arrive, read `~/.openclaw/hatch-notify.log` first (`skip reason=no-pane`: the pane could not be identified;
`send-failed http=... curl_exit=...`: the Gateway was not reached).

## Lessons from setup (2026-11-17, OpenClaw 2026.11.4)

- **The Gateway picks up an old Claude Code**: the LaunchAgent's PATH lacks `~/.local/bin`, so it used Homebrew's old
  `claude` and failed with "version 2.1.280 or newer is required". Fixed by registering
  `~/.openclaw/gateway-wrapper.sh` (prepends PATH, then starts OpenClaw) with
  `openclaw gateway install --wrapper ~/.openclaw/gateway-wrapper.sh --force`. `openclaw doctor --fix` may recreate
  the service without the wrapper; check the plist if the symptom returns.
- **Agent name**: the name chosen at onboarding (e.g. tinasha) must be in `hooks.allowedAgentIds` and in the env's
  `OPENCLAW_AGENT_ID`. install.sh takes the default from `openclaw agents list`. Sending a wake **before** onboarding
  leaves a stray `main` agent, and `agents.defaults.authInheritance.agentId` stays `main`, giving
  "Worker turn agent id does not match its placement". Fix with
  `openclaw config set agents.defaults.authInheritance.agentId <name>`.
- **Offline-only CLI commands**: `openclaw models auth list` and `openclaw memory status --deep` only work while the
  Gateway is stopped (`openclaw gateway stop --force` → run → `openclaw gateway start`). The final "save" of onboarding
  fails for the same reason, but the config is already saved.
- **Ghost text in the input line**: the last `❯` line of `hatch-capture` may show Claude Code's suggestion. It looks
  like unsent input, but `hatch-send` delivers with a single Enter.
- **Running through symlinks**: bin/ resolves its real location with `readlink -f` (it is called via `~/.local/bin`).
- **`tmux show-options -t "=name"`** returns nothing with the `=` prefix in tmux 3.6; use the bare name.
- **ssh inside `while read`** swallows the rest of the loop's input; the reap ended one session per pass until
  the loop read from its own file descriptor and ssh ran with `-n`.
- **OpenClaw's exec kills the process group** of a command when it returns. Anything the bridge must finish
  (ending a read-only session on close) runs in the foreground; the rest is detached with `setsid`.
- **Typing a multi-line message with `send-keys`** submits it line by line; paste it as a tmux buffer instead.

## Caveats

- OpenClaw's exec runs without approval by default (`tools.exec.mode` is full). That is a shell on the Mac reachable
  from chat; narrow it (e.g. `openclaw config set tools.exec.mode allowlist`) before connecting a public channel.
- Notifications are one line of text. Agent output is read by OpenClaw through `hatch-report` / `hatch-capture`
  (unverified output is never pushed into the wake).
- Codex asks to "trust" hooks on first use; start codex once and approve.
