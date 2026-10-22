# tmux-agent-hatch

![screenshot](./docs/screenshot.png)

A tmux plugin that runs **Claude Code** and **Codex CLI** in popups, one
session per project directory, and lists every running agent in a single
picker that shows what each one is doing.

Open the hatch, hand the agent some work, close it and get back to your
editor. Each session lives in its own nested tmux session, so closing the
popup never interrupts it. When you want to check in, `prefix` + `u` lists
every agent — Claude or Codex, launched here or by hand in some pane — with a
live `working` / `waiting` / `idle` status and a preview of its screen, and
jumps you straight to it. When an agent finishes or needs you, it rings a bell
that highlights the window you launched it from.

Built on [craftzdog/tmux-claude-hatch](https://github.com/craftzdog/tmux-claude-hatch)
and kept in sync with it. Just a few shell scripts.

## Why / philosophy

tmux-claude-hatch is deliberately Claude Code only. This repo exists for people
who run **more than one agent CLI** and want one hatch and one picker for all
of them, without giving up anything upstream does well.

- **Who it's for**
  - People who stay in their editor — (Neo)vim, Emacs — in the main tmux
    session and treat agents as something you open, delegate to, and close
  - People who use Claude Code *and* Codex side by side (e.g. one for
    implementation, one for review) and want to see both at a glance
  - People who'd rather have a small tool than a full agent dashboard
- **Who it's not for**
  - People whose focus is the agent's chat UI rather than the code
  - People who need a web UI, metrics, or session history

## Features

- **One picker for every agent** (`prefix` + `u`) — Claude Code and Codex
  rows side by side, several per project, plus any agent running loose in an
  ordinary pane.
- **Live status** per agent — `working` / `waiting` / `idle`. Claude Code
  reports its own; for Codex this plugin ships a tiny lifecycle hook that
  reports the same thing. Agents that need you sort to the top.
- **A live preview** of each agent's screen right in the picker.
- **Smart jump** — selecting an agent switches your client to the window it
  was launched from, then resumes it in a popup over it.
- **Two launchers** — `prefix` + `y` opens (or re-attaches to) Claude Code for
  the current directory, `prefix` + `Y` does the same for Codex.
- **Worktree launcher** — `prefix` + `W` creates a git worktree, a window to
  review it in, and an agent popup over that window, in one go.
- **Quick kill** (`ctrl-x`) and **copy location** (`ctrl-y`) from the picker.
- **Bell forwarding** — a bell in a popup session highlights the window you
  launched it from, for both agents.
- **Pane resize** with <kbd>Option</kbd> + arrows, and a **vi-style copy
  mode** that copies to the macOS clipboard — the two tmux niceties you end up
  wanting the moment you live in popups.
- **Upstream tracking** — the upstream scripts are vendored as a modified copy
  with a one-command sync (`tools/upstream-sync.sh`), so improvements to
  tmux-claude-hatch keep flowing in.

## Prerequisites

- **tmux ≥ 3.2** (for `display-popup`)
- **[fzf](https://github.com/junegunn/fzf)** — the picker UI
- **[jq](https://jqlang.org/)** — parses the agents' status files
- **[Claude Code](https://claude.com/claude-code)** ≥ 2.1.139 and/or
  **[Codex CLI](https://github.com/openai/codex)** ≥ 0.160 (lifecycle hooks)
- bash; macOS (clipboard bindings use `pbcopy`) or Linux (swap `pbcopy` for
  `wl-copy` / `xclip` in `hatch.tmux.conf`)

## Installation

```sh
git clone git@github.com:RuiHamada/tmux-agent-hatch.git ~/Git/tmux-agent-hatch
~/Git/tmux-agent-hatch/install.sh
```

`install.sh` is idempotent and keeps a backup next to every file it touches.
It does three things, each also available alone as `--tmux`, `--codex`,
`--claude`:

1. **tmux** — appends two lines to `~/.tmux.conf` and reloads a running server:
   ```tmux
   HATCH_DIR="/path/to/tmux-agent-hatch"
   source-file "$HATCH_DIR/hatch.tmux.conf"
   ```
2. **Codex** — writes (or merges into) `~/.codex/hooks.json` the hooks that
   report Codex's status. Codex asks you to trust new hooks once: start
   `codex` and confirm, or run `/hooks` inside it. Sessions already running
   when you trust them won't report until restarted.
3. **Claude Code** — merges into `~/.claude/settings.json` the hooks that ring
   the bell and keep the picker's cache fresh (the same ones upstream ships as
   a Claude Code plugin).

> **Keybinding note:** the plugin binds `prefix` + `y`, `Y` and `u`. If your
> config uses those elsewhere, change the [options](#options) or load the
> plugin after your own bindings so the one you want wins.

## Usage

| Key              | Action                                                                     |
| ---------------- | -------------------------------------------------------------------------- |
| `prefix` + `y`   | Launch (or re-attach to) **Claude Code** for the current directory, in a popup |
| `prefix` + `Y`   | Launch (or re-attach to) **Codex** for the current directory, in a popup   |
| `prefix` + `u`   | Open the agent picker                                                       |
| `prefix` + `W`   | New git worktree + a window for it + an agent popup over that window (asks for branch and agent) |
| `prefix` + `d`   | Close the popup and go back to your window; the agent keeps running        |
| `Option` + arrow | Resize the current pane by 3 cells                                         |

Inside the picker:

| Key                       | Action                                                                 |
| ------------------------- | ---------------------------------------------------------------------- |
| `enter`                   | Jump to the agent                                                      |
| `ctrl-x`                  | Kill the highlighted agent                                             |
| `ctrl-y`                  | Copy the highlighted agent's location (e.g. `codex-88074b0e:0.0`) and close |
| `↑` / `↓`, type to filter | fzf navigation                                                         |

Each row shows the agent (`claude` / `codex`), its status, how long ago it
last changed, where it lives (`session:window.pane`) and its directory.
Agents needing your attention (`waiting`, `idle`) sort to the top; set
`@claude_sort 'recent'` to sort by last activity instead.

Every running agent gets its own row — the picker identifies each by its
process, not by its tmux session. So several agents in one project show up
separately, as does one you started by hand in an ordinary pane (marked
`loose`).

To run a second agent in the same directory, open a new window inside the
popup (`prefix` + `c`, since the popup is an ordinary nested tmux session)
and start `claude` or `codex` there. Both appear in the picker and `enter`
jumps to the right window.

Copy mode (`prefix` + `[`, vi keys):

| Key           | Action                                 |
| ------------- | -------------------------------------- |
| `v` / `V`     | Start selection / line selection       |
| `Ctrl-v`      | Toggle rectangle selection             |
| `Enter`, `y`  | Copy to clipboard and leave copy mode  |
| `Esc`         | Leave copy mode                        |
| mouse drag    | Copy on release                        |

## Worktrees

`prefix` + `W` is for the "one agent per worktree" workflow. It asks for a
branch name and an agent (default `codex`) on the status line, then:

1. creates the worktree at `../<repo>-wt/<branch>` (reusing it if it exists;
   creating the branch if it doesn't),
2. opens a window named after the branch in your current session, with the
   worktree as its directory — this is where you review the code,
3. launches the agent popup over that window, so `prefix` + `d` drops you
   into the review window and the picker jumps back to it.

Each worktree gets its own agent session (the session name is derived from the
directory), so several worktrees of one repository run side by side.
Removing the worktree afterwards is up to you (`git worktree remove`).

Set `@hatch_worktree_dir` to put worktrees somewhere else; `@hatch_worktree_key`
to rebind.

## Options

Set any of these before the `source-file` line in `~/.tmux.conf` (defaults
shown). The `@claude_*` names are inherited from upstream and, where they are
not agent-specific, apply to both agents.

```tmux
set -g @claude_launch_key     'y'        # prefix key: Claude Code for current dir
set -g @codex_launch_key      'Y'        # prefix key: Codex for current dir
set -g @hatch_list_key        'u'        # prefix key: open the picker
set -g @hatch_worktree_key    'W'        # prefix key: worktree + window + popup
set -g @hatch_worktree_dir    ''         # where worktrees go; default ../<repo>-wt
set -g @claude_command        'claude'   # command run in new Claude sessions
set -g @codex_command         'codex'    # command run in new Codex sessions
set -g @claude_args           ''         # extra args for Claude
set -g @codex_args            ''         # extra args for Codex
set -g @claude_session_prefix 'claude-'  # tmux session name prefix (Claude)
set -g @codex_session_prefix  'codex-'   # tmux session name prefix (Codex)
set -g @claude_popup_width    '90%'      # popup width (both agents)
set -g @claude_popup_height   '90%'      # popup height (both agents)
set -g @claude_fzf_options    ''         # extra options passed to the fzf picker
set -g @claude_picker_cache   'on'       # paint the picker's first frame from a cache
set -g @claude_sort           'status'   # picker order: 'status' or 'recent'
set -g @claude_forward_bell   'on'       # highlight the origin window on a bell
```

For example, to skip permission prompts in launched sessions:

```tmux
set -g @claude_args '--dangerously-skip-permissions'
set -g @codex_args  '--full-auto'
```

## How status works

- **Claude Code** writes its own state to `~/.claude/sessions/*.json`. The
  picker reads it directly, falling back to `claude agents --json`.
- **Codex** has no such file, so `hooks/codex/status.sh` runs on
  `SessionStart` / `UserPromptSubmit` / `PermissionRequest` / `Stop` /
  `SessionEnd` and keeps an equivalent file under `~/.codex/hatch-status/`.
  It also rings the terminal bell on `Stop` and `PermissionRequest`.

The Codex TUI runs its session in Codex's app-server daemon, so its hooks fire
under the daemon rather than the TUI. The hook maps them back to the TUI by
matching the session's cwd against tmux panes that host a `codex` process.
Two Codex TUIs started in the same directory outside the hatch are therefore
told apart only by which one a session claimed first.

A stale status file (crashed agent, recycled pid) is ignored: a row only
counts while the pid still has the start time the file recorded.

Set `HATCH_DEBUG_LOG=/path/to/log` in the environment Codex starts from to
trace what the hook saw and did on each event.

## Customizing the fzf picker

`@claude_fzf_options` is passed straight to `fzf`, so you can add your own
bindings. A vim-style example:

```tmux
set -g @claude_fzf_options "\
  --prompt 'nav> ' \
  --bind 'j:down' \
  --bind 'k:up' \
  --bind 'q:abort' \
  --bind 'x:execute-silent(kill {3})+reload(sleep 0.3; \$HATCH_PICKER --list)' \
  --bind 'i:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'a:unbind(j,k,q,i,a,x)+change-prompt(filter> )' \
  --bind 'esc:rebind(j,k,q,i,a,x)+change-prompt(nav> )'"
```

`$HATCH_PICKER` (also exported as `$CLAUDE_PICKER` for upstream-compatible
snippets) is the picker's own path, for reloads.

## Tracking upstream

The upstream scripts live in `scripts/` and `hooks/` as modified copies, not a
submodule, so they can be changed here. `scripts/UPSTREAM` records the
upstream commit they were last synced to. To pull newer upstream commits:

```sh
tools/upstream-sync.sh --dry-run   # see the patch
tools/upstream-sync.sh             # apply as a 3-way patch, update scripts/UPSTREAM
```

Hunks that touch locally modified lines are left as conflict markers.

## Contributing

Issues and pull requests are welcome, in English or Japanese. Things that
would be especially useful:

- Linux clipboard support (`wl-copy` / `xclip`) behind an option
- A third agent (Gemini CLI, …): a launcher is a few lines in
  `scripts/launch.sh`; status needs a hook or file like the Codex one
- Reports of what breaks when Claude Code or Codex change their session
  formats

## Credits

The tmux side, the picker and the Claude Code integration are the work of
[Takuya Matsuyama](https://github.com/craftzdog) in
[tmux-claude-hatch](https://github.com/craftzdog/tmux-claude-hatch). This
repo adds the Codex half and the glue.

## License

[MIT](LICENSE). Includes code from tmux-claude-hatch, MIT © Takuya Matsuyama
(`LICENSE.tmux-claude-hatch`).
