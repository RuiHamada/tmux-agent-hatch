# openclaw/ — OpenClaw を窓口にして hatch のエージェントを使う

OpenClaw(チャット窓口)から Claude Code / Codex を起動するとき、OpenClaw 標準の ACP や code-agent プラグインは
端末のない子プロセスとして起動するため、tmux-agent-hatch のポップアップ・一覧・再表示が使えない。
このディレクトリは代わりに **OpenClaw から hatch と同じ tmux セッションを起動する**薄い橋で、
チャットで始めた作業を端末の picker(prefix+u)で開き直せる。

```
OpenClaw(チャット) --exec--> hatch-launch → tmux セッション claude-<hash>(picker に並ぶ)
                   <--wake--- hatch-notify ← Claude Code / Codex の hook(Stop / 権限 / 質問)
                   --exec--> hatch-capture / hatch-send で結果を読む・答える
```

| ファイル | 役割 |
|---|---|
| `bin/hatch-launch` | `<claude\|codex> <dir> [prompt]`。`scripts/launch.sh` と同じ名前規則でセッションを作る(ポップアップは出さない)。既存なら prompt を送る |
| `bin/hatch-list` | picker と同じ情報源(`scripts/agents.sh`)を TSV で |
| `bin/hatch-capture` / `bin/hatch-send` | 画面を読む / 文字を送る(tmux capture-pane / send-keys) |
| `bin/hatch-notify` | Claude / Codex の hook から OpenClaw の `POST /hooks/wake` へ短い通知。`~/.openclaw/hatch-notify.env` が無ければ何もしない。送った/送らなかった理由と HTTP ステータスを `~/.openclaw/hatch-notify.log` に残す(token・本文は書かない) |
| `hooks/claude.json`, `hooks/codex.json` | hook のテンプレート(hatch 本体の hooks.json とは別エントリ) |
| `skill/SKILL.md` | OpenClaw のスキル。`~/.openclaw/skills/hatch` に symlink される |
| `install.sh` / `uninstall.sh` | 入れる / 外す(`--purge` で OpenClaw 本体ごと)。`install.sh --remote` は ssh 先用 |
| `remote-setup.sh` | Mac から ssh 先を一括設定 |

## 入れる

```sh
npm install -g openclaw@latest --allow-scripts=openclaw   # 本体(消すのは npm uninstall -g openclaw)
~/Git/tmux-agent-hatch/openclaw/install.sh                  # 橋
openclaw onboard                                            # モデル接続(API キー等。対話)
openclaw gateway run                                        # まず前面で。常駐は openclaw gateway install
```

チャット(`openclaw dashboard` の Web UI、または繋いだチャネル)で「hatch で ~/Git/xxx の README を直して」のように頼む。

## ssh 先(workstation)のエージェントも扱う

workstation 側にも hatch が入っていれば、普段の接続(`gcloud workstations ssh`)に転送を 2 つ乗せるだけで、
その接続が生きている間、Mac の OpenClaw から workstation のエージェントも操作できる。別のトンネルや常駐は不要。

```sh
gcloud workstations ssh <name> ... -- -L 2222:127.0.0.1:22 -R 18790:127.0.0.1:18789
```

- `-L 2222:127.0.0.1:22`: Mac の localhost:2222 → workstation の sshd。`~/.ssh/config` の `Host gcp-workstation`(localhost:2222)経由で
  `hatch-launch --host gcp-workstation ...` が通る
- `-R 18790:127.0.0.1:18789`: workstation 側の hook の通知 → Mac の OpenClaw

初回だけ、接続した状態で Mac から `remote-setup.sh gcp-workstation` を実行する(workstation 側で `openclaw/install.sh --remote`、通知用 env の送付)。
以後、チャットで「workstation で ~/repos/xxx を直して」と言えば `hatch-launch --host gcp-workstation ...` になる。

## 消す

```sh
~/Git/tmux-agent-hatch/openclaw/uninstall.sh            # 橋だけ(hook・symlink・env・OpenClaw の hooks 設定)
~/Git/tmux-agent-hatch/openclaw/uninstall.sh --purge    # OpenClaw 本体と ~/.openclaw も
```

hatch 本体(`scripts/`、`hooks/`、`hatch.tmux.conf`)は一切変更していないので、このディレクトリを消せば元どおり。

## 通知元の画面の決め方(hatch-notify)

`TMUX_PANE` は信用しない。Codex は TUI から app-server daemon にセッションを渡すため、hook が daemon 側で動くと `TMUX_PANE` は daemon を最初に起動した画面の値(すでに閉じていたり別のセッションになっていたりする)になる。順に試す:

1. hook の親プロセスを辿って `claude` / `codex` のプロセスを見つけ、その tty を持つ pane
2. (Codex) `hooks/codex/status.sh` が書いた `~/.codex/hatch-status/<pid>.json` の `sessionId` から pid → tty → pane
3. payload の `cwd` と同じディレクトリで `claude` / `codex` を動かしている pane。複数あれば選ばず、候補のセッション名を列挙して通知する
4. `TMUX_PANE` がまだ存在する pane を指していればそれ

対象はセッション名(`claude-*` / `codex-*`)ではなく「tmux の pane の中で動いている claude / codex」で、`hatch-list` と同じ基準。手で作ったセッション(例: `graph-ws`)で動かしたエージェントも通知する。通知が来ないときはまず `~/.openclaw/hatch-notify.log` を見る(`skip reason=no-pane` なら画面を特定できなかった、`send-failed http=... curl_exit=...` なら Gateway に届いていない)。

## 導入時に踏んだ点(2026-11-17、OpenClaw 2026.11.4)

- **Gateway が古い Claude Code を拾う**: 常駐サービス(LaunchAgent)の PATH には `~/.local/bin` が無く、Homebrew の古い `claude` を使って
  "version 2.1.280 or newer is required" で失敗した。`~/.openclaw/gateway-wrapper.sh`(PATH を足して本体を起動)を
  `openclaw gateway install --wrapper ~/.openclaw/gateway-wrapper.sh --force` で登録して解決。`openclaw doctor --fix` が
  サービスを作り直すとラッパーが外れることがあるので、同じ症状が出たら plist を確認する。
- **エージェント名**: onboarding で付けた名前(例: tinasha)が `hooks.allowedAgentIds` と env の `OPENCLAW_AGENT_ID` に入っている必要がある。
  install.sh は `openclaw agents list` の default を自動で使う。onboarding **前**に wake を送ると `main` 名義の残骸ができ、
  `agents.defaults.authInheritance.agentId` が `main` のまま "Worker turn agent id does not match its placement" になる。
  その場合は `openclaw config set agents.defaults.authInheritance.agentId <name>`。
- **オフライン専用の CLI**: `openclaw models auth list` や `openclaw memory status --deep` は Gateway 停止中にしか動かない
  (`openclaw gateway stop --force` → 実行 → `openclaw gateway start`)。onboarding 最後の「保存」が同じ理由で失敗しても設定は保存されている。
- **入力欄の提案文**: `hatch-capture` の最後の `❯` 行に Claude Code の提案文(ghost text)が出る。未送信の入力と見間違えやすいが `hatch-send` は 1 回の Enter で送信できている。
- **symlink 経由の実行**: bin/ は `readlink -f` で実体の場所を解決する(`~/.local/bin` の symlink から呼ばれるため)。

## 注意

- OpenClaw の exec は既定で承認なし(`tools.exec.mode` が full)。チャットから Mac のシェルを叩ける状態になるので、公開チャネルに繋ぐ前に `openclaw config set tools.exec.mode allowlist` などで絞る。
- 通知(wake)はテキスト 1 行だけ。エージェントの出力は OpenClaw が `hatch-capture` で読みに行く(未検証の出力を wake に流さない)。
- Codex の hook は Codex が「trust」を求める。初回に codex を起動して承認する。
