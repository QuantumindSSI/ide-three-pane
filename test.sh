#!/bin/bash
#
# test.sh: verify this repository before installing or pushing.
#
# Runs, in order:
#   1. bash -n syntax check on every shell script
#   2. shellcheck on every shell script (skipped with a notice if absent)
#   3. a full install into a temporary HOME
#   4. file-presence and permission checks on everything installed
#   5. JSON validation of the generated opencode.jsonc (python3 or node)
#   6. a smoke test of the installed ide launcher (ide --tools)
#   7. an idempotency check: a second install run must exit 0
#   8. an em dash scan of first-party files (skills/ is third-party content
#      and is excluded)
#
# Exits 0 only when every check passes.

set -eu

ROOT="$(cd "$(dirname "$0")" && pwd -P)"
FAILED=0
TEST_HOME=""
TEST_LOG=""

fail() {
  echo "FAIL: $*"
  FAILED=1
}

ok() {
  echo "ok: $*"
}

cleanup() {
  if [ -n "$TEST_LOG" ] && [ -f "$TEST_LOG" ]; then
    rm -f "$TEST_LOG"
  fi
  if [ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}
trap cleanup EXIT

SCRIPTS="install.sh bin/ide bin/ide-focus bin/ide-mouse opencode/maintenance/compact-event-store.sh extras/mlx/mlx-serve extras/mlx/mlx-bench"

echo "== 1. syntax =="
for script in $SCRIPTS; do
  if [ ! -f "$ROOT/$script" ]; then
    fail "missing: $script"
    continue
  fi
  case "$(head -1 "$ROOT/$script")" in
    *python*)
      if command -v python3 >/dev/null 2>&1; then
        if python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$ROOT/$script"; then
          ok "python3 ast $script"
        else
          fail "python syntax: $script"
        fi
      else
        echo "skip: python3 not installed, cannot check $script"
      fi
      ;;
    *)
      if bash -n "$ROOT/$script"; then
        ok "bash -n $script"
      else
        fail "syntax: $script"
      fi
      ;;
  esac
done

echo "== 2. shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  for script in $SCRIPTS; do
    if [ -f "$ROOT/$script" ] && shellcheck -S warning "$ROOT/$script"; then
      ok "shellcheck $script"
    else
      fail "shellcheck: $script"
    fi
  done
else
  echo "skip: shellcheck not installed (macOS: brew install shellcheck; Debian/Ubuntu: sudo apt install shellcheck)"
fi

echo "== 3. install into a temporary HOME =="
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/ide-test-home.XXXXXX")"
TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/ide-test-log.XXXXXX")"
if HOME="$TEST_HOME" bash "$ROOT/install.sh" >"$TEST_LOG" 2>&1; then
  ok "install.sh exit 0"
else
  fail "install.sh exited non-zero; log follows:"
  cat "$TEST_LOG"
fi

echo "== 4. installed files =="
INSTALLED=".local/bin/ide .local/bin/ide-focus .local/bin/ide-mouse .tmux.conf .config/nvim/init.lua .config/opencode/opencode.jsonc .config/opencode/package.json .config/opencode/package-lock.json .config/opencode/maintenance/compact-event-store.sh .config/opencode/skills/turnstile-spin/SKILL.md .config/opencode/skills/cloudflare/SKILL.md"
for file in $INSTALLED; do
  if [ -f "$TEST_HOME/$file" ]; then
    ok "present: $file"
  else
    fail "missing after install: $file"
  fi
done
for file in .local/bin/ide .local/bin/ide-focus .local/bin/ide-mouse; do
  if [ -x "$TEST_HOME/$file" ]; then
    ok "executable: $file"
  else
    fail "not executable: $file"
  fi
done

echo "== 5. generated opencode.jsonc is valid JSON =="
if command -v python3 >/dev/null 2>&1; then
  if python3 -m json.tool "$TEST_HOME/.config/opencode/opencode.jsonc" >/dev/null 2>&1; then
    ok "python3 json.tool"
  else
    fail "opencode.jsonc is not valid JSON"
  fi
elif command -v node >/dev/null 2>&1; then
  if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TEST_HOME/.config/opencode/opencode.jsonc"; then
    ok "node JSON.parse"
  else
    fail "opencode.jsonc is not valid JSON"
  fi
else
  fail "no python3 or node available to validate JSON"
fi

echo "== 6. ide launcher smoke test =="
if HOME="$TEST_HOME" "$TEST_HOME/.local/bin/ide" --tools >/dev/null 2>&1; then
  ok "ide --tools exit 0"
else
  fail "ide --tools failed under the temporary HOME"
fi

echo "== 7. idempotency =="
if HOME="$TEST_HOME" bash "$ROOT/install.sh" >"$TEST_LOG" 2>&1; then
  if grep -q "up to date" "$TEST_LOG"; then
    ok "second run exits 0 and reports up to date"
  else
    fail "second run exited 0 but reported no up to date lines; log follows:"
    cat "$TEST_LOG"
  fi
else
  fail "second install run exited non-zero; log follows:"
  cat "$TEST_LOG"
fi

echo "== 8. em dash scan (first-party files) =="
# printf with octal escapes: bash 3.2 (macOS default) does not support \u escapes.
EMDASH="$(printf '\342\200\224')"
if grep -rl "$EMDASH" "$ROOT" 2>/dev/null | grep -v "/skills/" >"$TEST_LOG"; then
  fail "em dash (U+2014) found in:"
  cat "$TEST_LOG"
else
  ok "no em dashes in first-party files"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  exit 0
fi
echo "SOME CHECKS FAILED"
exit 1
