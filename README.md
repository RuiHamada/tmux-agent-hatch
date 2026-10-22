# tmux-agent-hatch

Run **Claude Code** and **Codex CLI** in tmux popups, one session per project
directory. Open the hatch, hand the agent some work, close the popup and get
back to your editor; the session keeps running in a nested tmux session.

Built on top of [craftzdog/tmux-claude-hatch](https://github.com/craftzdog/tmux-claude-hatch)
(vendored as a git submodule, used unmodified) and adds:

- a Codex launcher and session list on separate keys
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
| `prefix` + `u`   | Claude agent picker with live status (upstream)               |
| `prefix` + `Y`   | Codex popup for the current directory                         |
| `prefix` + `U`   | Codex session list (`enter` open, `ctrl-x` kill)              |
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
set -g @codex_list_key       'U'
set -g @codex_command        'codex'
set -g @codex_args           ''        # e.g. '--full-auto'
set -g @codex_session_prefix 'codex-'
```

Popup size is shared: `@claude_popup_width` / `@claude_popup_height`.

## Limitations

- The Codex list shows name, age and path only. Codex writes no live status
  file the way Claude Code does, so there is no working/waiting indicator.
- No bell forwarding for Codex yet. Codex's `notify` hook could ring one, but
  it accepts a single command, so it needs a wrapper if you already use it.

## Updating the upstream plugin

```sh
git submodule update --remote vendor/tmux-claude-hatch
```

## License

MIT. The vendored `tmux-claude-hatch` is MIT © Takuya Matsuyama.
