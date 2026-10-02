#!/bin/bash
#
# install.sh: install the three-pane agentic IDE on any machine.
#
# Installs:
#   bin/ide, ide-focus, ide-mouse   -> $BIN_DIR        (default ~/.local/bin)
#   config/tmux.conf                -> ~/.tmux.conf
#   config/nvim/init.lua            -> ~/.config/nvim/init.lua
#   opencode/                       -> ~/.config/opencode/
#     opencode.jsonc is generated here, with machine-specific MCP and
#     provider blocks included only when their prerequisites exist.
#     skills/ and maintenance/ are copied as-is.
#
# Options:
#   --bin-dir DIR   install the bin scripts into DIR (default ~/.local/bin)
#   --with-mlx      also install the mlx extras (mlx-serve, mlx-bench and the
#                   detokenizer fix helpers). Apple Silicon + MLX only.
#   --no-opencode   skip the opencode config, skills and maintenance scripts
#   --no-nvim       skip the nvim config
#   --no-tmux       skip the tmux config
#   --no-path       never touch any shell rc file
#   -h | --help     this message
#
# Existing files that differ are backed up to
#   ${XDG_DATA_HOME:-~/.local/share}/ide-three-pane/backups/<timestamp>/
# before anything is overwritten. The installer is idempotent: re-running it
# skips files that are already identical.

set -eu

BIN_DIR="$HOME/.local/bin"
WITH_MLX=0
DO_OPENCODE=1
DO_NVIM=1
DO_TMUX=1
DO_PATH=1
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ide-three-pane/backups/$STAMP"

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
OPENCODE_DIR="$HOME/.config/opencode"
NVIM_DIR="$HOME/.config/nvim"
TMP_JSON=""

usage() {
  sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

cleanup() {
  if [ -n "$TMP_JSON" ] && [ -f "$TMP_JSON" ]; then
    rm -f "$TMP_JSON"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- utilities

# JSON string escape for paths interpolated into the generated config.
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# install_file SRC DST MODE: copy SRC to DST, backing up a differing DST.
# MODE is a chmod argument or empty for "leave as the source mode".
install_file() {
  local src="$1" dst="$2" mode="$3" name
  if [ ! -f "$src" ]; then
    echo "install: source missing: $src" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      if [ -n "$mode" ]; then
        chmod "$mode" "$dst"
      fi
      echo "install: up to date: $dst"
      return 0
    fi
    name=$(printf '%s' "$dst" | sed 's|^/||; s|/|_|g')
    mkdir -p "$BACKUP_DIR"
    cp "$dst" "$BACKUP_DIR/$name"
    cp "$src" "$dst"
    if [ -n "$mode" ]; then
      chmod "$mode" "$dst"
    fi
    echo "install: updated $dst (previous copy: $BACKUP_DIR/$name)"
    return 0
  fi
  cp "$src" "$dst"
  if [ -n "$mode" ]; then
    chmod "$mode" "$dst"
  fi
  echo "install: installed $dst"
}

# copy_tree SRC_PARENT NAME DST: merge directory NAME from SRC_PARENT into
# DST. A tar pipe overwrites file contents in place and never nests, unlike
# cp -R when the destination directory already exists.
copy_tree() {
  local src_parent="$1" name="$2" dst="$3"
  if [ ! -d "$src_parent/$name" ]; then
    echo "install: source missing: $src_parent/$name" >&2
    return 1
  fi
  mkdir -p "$dst"
  (cd "$src_parent" && tar cf - "$name") | (cd "$dst" && tar xf -)
  echo "install: merged $src_parent/$name into $dst/$name"
}

warn_missing() {
  local bin="$1" hint="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "install: WARNING: $bin not found. $hint" >&2
  fi
}

# add_to_path BIN_DIR: append a guarded PATH entry to the shell rc when
# BIN_DIR is not already on PATH. Unknown shells get a manual instruction.
add_to_path() {
  local bin_dir="$1" rc
  case ":$PATH:" in
    *":$bin_dir:"*)
      echo "install: $bin_dir is already on PATH"
      return 0
      ;;
  esac
  case "${SHELL##*/}" in
    zsh) rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)
      echo "install: add $bin_dir to your PATH manually (unrecognised shell: ${SHELL:-unset})" >&2
      return 0
      ;;
  esac
  if [ -f "$rc" ] && grep -q "added by ide-three-pane installer" "$rc" 2>/dev/null; then
    echo "install: $rc already has the installer PATH entry"
    return 0
  fi
  printf '\n# added by ide-three-pane installer\nexport PATH="%s:$PATH"\n' "$bin_dir" >> "$rc"
  echo "install: appended PATH entry to $rc (open a new shell to pick it up)"
}

# ------------------------------------------------- opencode config assembly

# write_opencode_config OUT: assemble opencode.jsonc. Every machine-specific
# block is included only when its prerequisite exists, so the generated file
# is valid on any machine. Optional blocks are always emitted with a leading
# comma, which is safe because the entries before them are unconditional.
write_opencode_config() {
  local out="$1" home
  home="$(json_escape "$HOME")"
  {
    printf '{\n'
    printf '  "$schema": "https://opencode.ai/config.json"'

    if [ -f "$HOME/mcp-servers/CTO-MCP/persona_constitution/data/DIRECTIVES.md" ]; then
      printf ',\n  "instructions": [\n    "%s"\n  ]' \
        "$home/mcp-servers/CTO-MCP/persona_constitution/data/DIRECTIVES.md"
      echo "install: opencode: instructions block included (persona constitution found)" >&2
    else
      echo "install: opencode: instructions block skipped (no persona constitution under ~/mcp-servers/CTO-MCP)" >&2
    fi

    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
      printf ',\n  "provider": {\n    "mlx": {\n      "npm": "@ai-sdk/openai-compatible",\n      "name": "MLX (local)",\n      "options": {\n        "baseURL": "http://127.0.0.1:8080/v1"\n      },\n      "models": {\n        "%s": {\n          "name": "Qwen2.5-Coder-7B MLX 4bit (local)",\n          "limit": { "context": 32768, "output": 8192 },\n          "modalities": { "input": ["text"], "output": ["text"] },\n          "tool_call": true\n        }\n      }\n    }\n  }' \
        "$home/.lmstudio/models/mlx-community/Qwen2.5-Coder-7B-Instruct-4bit"
      echo "install: opencode: mlx provider included (Apple Silicon)" >&2
    else
      echo "install: opencode: mlx provider skipped (not Apple Silicon)" >&2
    fi

    printf ',\n  "mcp": {\n'
    printf '    "cloudflare": {\n      "type": "remote",\n      "url": "https://mcp.cloudflare.com/mcp",\n      "enabled": true,\n      "oauth": {},\n      "timeout": 15000\n    },\n'
    printf '    "cloudflare-docs": {\n      "type": "remote",\n      "url": "https://docs.mcp.cloudflare.com/mcp",\n      "enabled": true,\n      "oauth": false,\n      "timeout": 15000\n    }'

    if [ -x "$HOME/mcp-servers/CTO-MCP/.venv/bin/python" ] && [ -f "$HOME/mcp-servers/CTO-MCP/persona_constitution/server.py" ]; then
      printf ',\n    "persona-constitution": {\n      "type": "local",\n      "command": [\n        "%s",\n        "%s"\n      ],\n      "enabled": true,\n      "timeout": 15000\n    }' \
        "$home/mcp-servers/CTO-MCP/.venv/bin/python" \
        "$home/mcp-servers/CTO-MCP/persona_constitution/server.py"
      echo "install: opencode: persona-constitution MCP included" >&2
    else
      echo "install: opencode: persona-constitution MCP skipped (clone CTO-MCP to ~/mcp-servers/CTO-MCP and create its .venv to enable)" >&2
    fi

    if [ -x "$HOME/lummenna/.venv/bin/python" ]; then
      printf ',\n    "lummenna": {\n      "type": "local",\n      "command": [\n        "%s",\n        "-m",\n        "lummenna.integrations.mcp_server"\n      ],\n      "cwd": "%s",\n      "enabled": true,\n      "timeout": 60000,\n      "environment": {\n        "LUMMENNA_DEVICE": "generic",\n        "LUMMENNA_STORE_PATH": "%s",\n        "LUMMENNA_MODEL_PATH": "%s",\n        "PYTHONDONTWRITEBYTECODE": "1"\n      }\n    }' \
        "$home/lummenna/.venv/bin/python" \
        "$home/lummenna" \
        "$home/lummenna/.lummenna/store" \
        "$home/lummenna/.lummenna/models"
      echo "install: opencode: lummenna MCP included" >&2
    else
      echo "install: opencode: lummenna MCP skipped (clone lummenna to ~/lummenna and create its .venv to enable)" >&2
    fi

    printf '\n  }\n}\n'
  } > "$out"
}

# --------------------------------------------------------------------- main

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      --bin-dir)
        [ "$#" -ge 2 ] || { echo "install: --bin-dir needs a value." >&2; return 1; }
        BIN_DIR="$2"
        shift
        ;;
      --bin-dir=*)
        BIN_DIR="${1#--bin-dir=}"
        ;;
      --with-mlx) WITH_MLX=1 ;;
      --no-opencode) DO_OPENCODE=0 ;;
      --no-nvim) DO_NVIM=0 ;;
      --no-tmux) DO_TMUX=0 ;;
      --no-path) DO_PATH=0 ;;
      *)
        echo "install: unknown option $1" >&2
        usage >&2
        return 1
        ;;
    esac
    shift
  done

  BIN_DIR="${BIN_DIR%/}"
  for required in bin config opencode; do
    if [ ! -d "$SOURCE_DIR/$required" ]; then
      echo "install: run this script from the repository root ($required/ missing next to install.sh)" >&2
      return 1
    fi
  done

  echo "install: source: $SOURCE_DIR"
  echo "install: backups: $BACKUP_DIR"

  # 1) bin scripts
  install_file "$SOURCE_DIR/bin/ide" "$BIN_DIR/ide" "755"
  install_file "$SOURCE_DIR/bin/ide-focus" "$BIN_DIR/ide-focus" "755"
  install_file "$SOURCE_DIR/bin/ide-mouse" "$BIN_DIR/ide-mouse" "755"

  # 2) tmux config
  if [ "$DO_TMUX" -eq 1 ]; then
    install_file "$SOURCE_DIR/config/tmux.conf" "$HOME/.tmux.conf" ""
  fi

  # 3) nvim config
  if [ "$DO_NVIM" -eq 1 ]; then
    install_file "$SOURCE_DIR/config/nvim/init.lua" "$NVIM_DIR/init.lua" ""
  fi

  # 4) opencode config, skills, maintenance
  if [ "$DO_OPENCODE" -eq 1 ]; then
    mkdir -p "$OPENCODE_DIR"
    TMP_JSON="$(mktemp "${TMPDIR:-/tmp}/ide-opencode.XXXXXX")"
    write_opencode_config "$TMP_JSON"
    install_file "$TMP_JSON" "$OPENCODE_DIR/opencode.jsonc" ""
    copy_tree "$SOURCE_DIR/opencode" "skills" "$OPENCODE_DIR"
    copy_tree "$SOURCE_DIR/opencode" "maintenance" "$OPENCODE_DIR"
    install_file "$SOURCE_DIR/opencode/package.json" "$OPENCODE_DIR/package.json" ""
    install_file "$SOURCE_DIR/opencode/package-lock.json" "$OPENCODE_DIR/package-lock.json" ""
  fi

  # 5) mlx extras
  if [ "$WITH_MLX" -eq 1 ]; then
    install_file "$SOURCE_DIR/extras/mlx/mlx-serve" "$BIN_DIR/mlx-serve" "755"
    install_file "$SOURCE_DIR/extras/mlx/mlx-bench" "$BIN_DIR/mlx-bench" "755"
    install_file "$SOURCE_DIR/extras/mlx/apply-detok-fix.py" "$HOME/.local/share/mlx-server/apply-detok-fix.py" "755"
    install_file "$SOURCE_DIR/extras/mlx/hf-parallel-fetch.py" "$HOME/.local/share/mlx-server/hf-parallel-fetch.py" "755"
  fi

  # 6) PATH
  if [ "$DO_PATH" -eq 1 ]; then
    add_to_path "$BIN_DIR"
  fi

  # 7) prerequisite warnings
  warn_missing "tmux" "the ide launcher needs it (macOS: brew install tmux; Debian/Ubuntu: sudo apt install tmux)."
  warn_missing "nvim" "the editor pane defaults to it (macOS: brew install neovim; Debian/Ubuntu: sudo apt install neovim)."
  warn_missing "opencode" "the top-right harness defaults to it (curl -fsSL https://opencode.ai/install | bash)."

  echo ""
  echo "Done."
  echo "  Restart any running opencode so it reads the new config."
  echo "  Reload tmux config with: tmux source-file ~/.tmux.conf"
  echo "  Then open a project with: ide [dir]   (or: ide --pick)"
  return 0
}

main "$@"
