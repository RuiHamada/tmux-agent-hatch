# tmux-agent-hatch

Run **Claude Code** and **Codex CLI** in tmux popups, one session per project
directory, and jump between them from a single picker that shows what each
agent is doing. Open the hatch, hand the agent some work, close the popup and
get back to your editor; the session keeps running in a nested tmux session.

A modified copy of [craftzdog/tmux-claude-hatch](https://github.com/craftzdog/tmux-claude-hatch)
(MIT, see `LICENSE.tmux-claude-hatch` and `scripts/UPSTREAM`) that adds:

- a Codex launcher next to the Claude one
- Codex rows in the picker, with `working` / `waiting` / `idle` status driven by
  Codex's lifecycle hooks
- pane resizing with <kbd>Option</kbd> + arrows
- vi-style copy mode that copies to the macOS clipboard

## Requirements

- tmux ≥ 3.2 (`display-popup`), fzf, jq
- [Claude Code](https://claude.com/claude-code) ≥ 2.1.139 and/or
  [Codex CLI](https://github.com/openai/codex) with hooks (0.160+)
- macOS or Linux (clipboard bindings use `pbcopy`; swap them on Linux)

## Install

```sh
git clone git@github.com:RuiHamada/tmux-agent-hatch.git ~/Git/tmux-agent-hatch
~/Git/tmux-agent-hatch/install.sh
```

`install.sh` is idempotent and does three things (each also available alone
with `--tmux`, `--codex`, `--claude`):

1. appends to `~/.tmux.conf` and reloads a running server:
   ```tmux
   HATCH_DIR="/path/to/tmux-agent-hatch"
   source-file "$HATCH_DIR/hatch.tmux.conf"
   ```
2. writes (or merges into) `~/.codex/hooks.json` so Codex reports its status.
   Codex asks you to trust new hooks once: start `codex` and confirm, or run
   `/hooks` inside it.
3. merges the Claude Code hooks into `~/.claude/settings.json` (bell + picker
   cache refresh). A backup is kept next to any file it edits.

## Keys

| Key              | Action                                                            |
| ---------------- | ----------------------------------------------------------------- |
| `prefix` + `y`   | Claude Code popup for the current directory                       |
| `prefix` + `Y`   | Codex popup for the current directory                             |
| `prefix` + `u`   | Picker: every running agent, Claude and Codex, with live status   |
| `prefix` + `d`   | Close the popup; the session keeps running                        |
| `Option` + arrow | Resize the current pane by 3 cells                                |

Inside the picker:

| Key                       | Action                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `enter`                   | Jump to the agent (reopens its popup over the origin window)  |
| `ctrl-x`                  | Kill the highlighted agent                                    |
| `ctrl-y`                  | Copy the agent's `session:window.pane` target and close       |
| `↑` / `↓`, type to filter | fzf navigation                                                |

Agents needing you (`waiting`, `idle`) sort to the top. Agents started by hand
in an ordinary pane show up too, marked `loose`.

Copy mode (`prefix` + `[`, vi keys):

| Key           | Action                                 |
| ------------- | -------------------------------------- |
| `v` / `V`     | Start selection / line selection       |
| `Ctrl-v`      | Toggle rectangle selection             |
| `Enter`, `y`  | Copy to clipboard and leave copy mode  |
| `Esc`         | Leave copy mode                        |
| mouse drag    | Copy on release                        |

## How status works

- **Claude Code** writes its own state to `~/.claude/sessions/*.json`; the
  picker reads it directly (falling back to `claude agents --json`).
- **Codex** has no such file, so `hooks/codex/status.sh` runs on
  `SessionStart` / `UserPromptSubmit` / `PermissionRequest` / `Stop` /
  `SessionEnd` and keeps an equivalent file under `~/.codex/hatch-status/`.
  It also rings the terminal bell on `Stop` and `PermissionRequest`, which the
  tmux side forwards to the window you launched the agent from.

A stale status file (crashed agent, recycled pid) is ignored: a row only
counts while the pid still has the start time the file recorded.

## Options

Set before `source-file` in `~/.tmux.conf` (defaults shown in
`hatch.tmux.conf`):

```tmux
set -g @claude_launch_key     'y'
set -g @codex_launch_key      'Y'
set -g @hatch_list_key        'u'
set -g @claude_command        'claude'
set -g @codex_command         'codex'
set -g @claude_args           ''         # e.g. '--dangerously-skip-permissions'
set -g @codex_args            ''         # e.g. '--full-auto'
set -g @claude_session_prefix 'claude-'
set -g @codex_session_prefix  'codex-'
set -g @claude_popup_width    '90%'      # shared by both agents
set -g @claude_popup_height   '90%'
set -g @claude_sort           'status'   # or 'recent'
set -g @claude_picker_cache   'on'
set -g @claude_forward_bell   'on'
set -g @claude_fzf_options    ''         # extra fzf options for the picker
```

The `@claude_*` names are kept as-is from upstream so its documentation still
applies.

## Tracking upstream

The upstream scripts live in `scripts/` and `hooks/` as modified copies, not a
submodule, so they can be changed here. To pull newer upstream commits:

```sh
tools/upstream-sync.sh --dry-run   # see the patch
tools/upstream-sync.sh             # apply as a 3-way patch, update scripts/UPSTREAM
```

Hunks that touch locally modified lines are left as conflict markers.

## License

MIT. Includes code from tmux-claude-hatch, MIT © Takuya Matsuyama.
