if [ "${HATCH_TEST_HOST:-}" = hatch-test-loopback ]; then
  cat >"$W/literal" <<'TEXT'
Review the maintainer's notes.
Keep the literal examples `hatch_quote_probe` and $(hatch_quote_probe) in the document.
TEXT
  cat >"$W/bin/hatch_quote_probe" <<'PROBE'
#!/bin/sh
: >"$HATCH_TEST_ROOT/evaluated"
PROBE
  chmod +x "$W/bin/hatch_quote_probe"
  literal="$(cat "$W/literal"; echo .)"; literal="${literal%.}"
  result="$(HATCH_TEST_LITERAL="$W/literal" /bin/bash "$BIN/hatch-launch" --host "$HATCH_TEST_HOST" --expect literal --readonly --slug literal codex "$REPO" "$literal")"
  literal_out="$(field "$result" out)"
  check "remote multiline prompt is byte-identical inert data" '[ -f "$literal_out/meta.json" ] && jq -j .prompt "$literal_out/meta.json" | cmp -s - "$W/literal" && [ ! -e "$W/evaluated" ]'
  if command -v zsh >/dev/null; then
    check "zsh preserves a literal leading equals argument" '[ "$(HATCH_TEST_LOGIN_SHELL=zsh /bin/bash -c '\''HATCH_NO_DISPATCH=1 . "$1/_remote.sh"; hatch_remote_cmd hatch-test-loopback printf "%s" "=hatch-literal:"'\'' _ "$BIN")" = "=hatch-literal:" ]'
  fi
fi
