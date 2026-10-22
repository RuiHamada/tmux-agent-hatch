# tmux-agent-hatch

Run **Claude Code** and **Codex CLI** in tmux popups, one session per project
directory. Open the hatch, hand the agent some work, close the popup and get
back to your editor; the session keeps running in a nested tmux session.

Built on top of [craftzdog/tmux-claude-hatch](https://github.com/craftzdog/tmux-claude-hatch)
(vendored as a git submodule, used unmodified) and adds:

- a Codex launcher, and one list of every agent popup (Claude and Codex)
- pane resizing with <kbd>Option</kbd> + arrows
- vi-style copy mode that copies to the macOS clipboard

## Requirements

- tmux ≥ 3.2 (`display-popup`), fzf, jq
- [Claude Code](https://claude.com/claude-code) and/or [Codex CLI](https://github.com/openai/codex)
- macOS (clipboard uses `pbcopy`)

## Install

```sh
git clone --recurse-submodules git@github.com:RuiHamada/tmux-agent-hatch.git ~/Git/tmux-agent-hatch
~/Git/tmux-agent-hatch/install.sh
```

`install.sh` appends two lines to `~/.tmux.conf` and reloads a running server:

```tmux
HATCH_DIR="/path/to/tmux-agent-hatch"
source-file "$HATCH_DIR/hatch.tmux.conf"
```

Optional, once, inside Claude Code (bell + picker cache for the Claude side):

```
/plugin marketplace add craftzdog/tmux-claude-hatch
/plugin install tmux-claude-hatch@tmux-claude-hatch
```

## Keys

| Key              | Action                                                        |
| ---------------- | ------------------------------------------------------------- |
| `prefix` + `y`   | Claude Code popup for the current directory (upstream)        |
| `prefix` + `Y`   | Codex popup for the current directory                         |
| `prefix` + `u`   | All agent popups, Claude and Codex (`enter` open, `ctrl-x` kill) |
| `prefix` + `d`   | Close the popup; the session keeps running                    |
| `Option` + arrow | Resize the current pane by 3 cells                            |

Copy mode (`prefix` + `[`, vi keys):

| Key           | Action                                 |
| ------------- | -------------------------------------- |
| `v` / `V`     | Start selection / line selection       |
| `Ctrl-v`      | Toggle rectangle selection             |
| `Enter`, `y`  | Copy to clipboard and leave copy mode  |
| `Esc`         | Leave copy mode                        |
| mouse drag    | Copy on release                        |

## Options

Set before `source-file` in `~/.tmux.conf`. Upstream `@claude_*` options work as
documented in the upstream README; the Codex side mirrors them:

```tmux
set -g @codex_launch_key     'Y'
set -g @codex_list_key       'u'        # all-agents list
set -g @codex_command        'codex'
set -g @codex_args           ''        # e.g. '--full-auto'
set -g @codex_session_prefix 'codex-'
set -g @hatch_list_prefixes  'claude- codex-'   # session-name prefixes listed by prefix+u
```

Popup size is shared: `@claude_popup_width` / `@claude_popup_height`.

## Limitations

- The all-agents list (`prefix` + `u`) shows kind, age and path only; it is
  driven by tmux session names, not by the agents. Codex writes no live status
  file the way Claude Code does, so there is no working/waiting indicator there.
  The upstream Claude-only picker is unbound; set your own `@claude_list_key`
  and remove the `unbind-key` line in `hatch.tmux.conf` if you want it back.
- No bell forwarding for Codex yet. Codex's `notify` hook could ring one, but
  it accepts a single command, so it needs a wrapper if you already use it.

## Updating the upstream plugin

```sh
git submodule update --remote vendor/tmux-claude-hatch
```

## License

MIT. The vendored `tmux-claude-hatch` is MIT © Takuya Matsuyama.
