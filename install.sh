#!/bin/bash
#
# install.sh: install the three-pane agentic IDE on any machine.
#
# Installs:
#   bin/ide, ide-focus, ide-mouse   -> $BIN_DIR        (default ~/.local/bin)
#   config/tmux.conf                -> ~/.tmux.conf
#   config/nvim/init.lua            -> ~/.config/nvim/init.lua
#   docs/neovim-guide.md            -> ~/.local/share/ide-three-pane/docs/
#   opencode/                       -> ~/.config/opencode/
#     opencode.jsonc is generated here, with machine-specific MCP and
#     provider blocks included only when their prerequisites exist.
#     skills/ and maintenance/ are copied as-is.
#
# Harness detection: installed agent harnesses (opencode, omp, hermes,
# claude, codex, gemini, aider, crush, goose) and editors (nvim, vim, helix,
# emacs, nano, micro) are detected, reported, and offered for the three
# panes. Interactive runs ask which to use and write the choices to
# ~/.config/ide/config as defaults for the ide launcher; non-interactive
# runs honour --editor/--top/--bottom and otherwise skip.
#
# Options:
#   --bin-dir DIR   install the bin scripts into DIR (default ~/.local/bin)
#   --with-mlx      also install the mlx extras (mlx-serve, mlx-bench and the
#                   detokenizer fix helpers). Apple Silicon + MLX only.
#   --no-opencode   skip the opencode config, skills and maintenance scripts
#   --no-nvim       skip the nvim config
#   --no-tmux       skip the tmux config
#   --no-path       never touch any shell rc file
#   --no-pick       skip the interactive pane selection (flags still apply)
#   --editor SPEC   default for the left pane, e.g. "nvim" or "hx ."
#   --top SPEC      default for the top-right pane, e.g. "opencode"
#   --bottom SPEC   default for the bottom-right pane, e.g. "hermes"
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
DO_PICK=1
EDITOR_SPEC=""
TOP_SPEC=""
BOTTOM_SPEC=""
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ide-three-pane/backups/$STAMP"

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
OPENCODE_DIR="$HOME/.config/opencode"
NVIM_DIR="$HOME/.config/nvim"
GUIDE_DIR="$HOME/.local/share/ide-three-pane/docs"
IDE_CONFIG_DIR="$HOME/.config/ide"
IDE_CONFIG_FILE="$IDE_CONFIG_DIR/config"
TMP_JSON=""

usage() {
  sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//'
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

# ------------------------------------------------- harness and editor menus

editors() {
  printf '%s\n' \
    'nvim|nvim .' \
    'vim|vim .' \
    'helix|hx .' \
    'emacs|emacs -nw .' \
    'nano|nano .' \
    'micro|micro .'
}

harnesses() {
  printf '%s\n' \
    'opencode|opencode' \
    'omp|omp' \
    'hermes|hermes' \
    'claude|claude' \
    'codex|codex' \
    'gemini|gemini' \
    'aider|aider' \
    'crush|crush' \
    'goose|goose'
}

# resolve_spec SPEC editor|harness: fail unless SPEC is a catalog name or a
# command whose binary exists.
resolve_spec() {
  local spec="$1" kind="$2" catalog line base
  if [ "$kind" = editor ]; then catalog=$(editors); else catalog=$(harnesses); fi
  line=$(printf '%s\n' "$catalog" | awk -F'|' -v s="$spec" '$1 == s { print; exit }')
  if [ -n "$line" ]; then
    base=$(printf '%s' "$line" | cut -d'|' -f2- | awk '{ print $1 }')
    if ! command -v "$base" >/dev/null 2>&1; then
      echo "install: $kind '$spec' needs '$base', which is not installed." >&2
      return 1
    fi
    return 0
  fi
  base=$(printf '%s' "$spec" | awk '{ print $1 }')
  if [ -z "$base" ]; then
    echo "install: empty $kind command." >&2
    return 1
  fi
  if ! command -v "$base" >/dev/null 2>&1; then
    echo "install: $kind '$spec' needs '$base', which is not installed." >&2
    return 1
  fi
}

# ready_harnesses NAME...: print the catalog entries whose binary exists.
ready_harnesses() {
  local catalog="$1" line name cmd base
  printf '%s\n' "$catalog" | while IFS='|' read -r name cmd; do
    [ -n "$name" ] || continue
    base=$(printf '%s' "$cmd" | awk '{ print $1 }')
    if command -v "$base" >/dev/null 2>&1; then
      printf '%s ' "$name"
    fi
  done
}

# prompt_slot KIND TITLE DEFAULT_SPEC: interactive menu over the catalog.
# Installed tools are marked; a pick of a missing tool is rejected. Prints
# the chosen SPEC (catalog name or custom command) on stdout. Enter keeps
# the default; c) enters a custom command; EOF returns 2 (cancel).
prompt_slot() {
  local kind="$1" title="$2" default_spec="$3"
  local catalog line name cmd base i ans count
  if [ "$kind" = editor ]; then catalog=$(editors); else catalog=$(harnesses); fi
  echo "" >&2
  echo "$title (current default: ${default_spec:-none}):" >&2
  i=0
  while IFS='|' read -r name cmd; do
    [ -n "$name" ] || continue
    i=$((i + 1))
    base=$(printf '%s' "$cmd" | awk '{ print $1 }')
    if command -v "$base" >/dev/null 2>&1; then
      printf '  %2d  %-9s %-16s installed\n' "$i" "$name" "$cmd" >&2
    else
      printf '  %2d  %-9s %-16s not installed\n' "$i" "$name" "$cmd" >&2
    fi
  done <<EOF
$catalog
EOF
  printf '  c) custom command\n' >&2
  printf 'choice [number, c, or Enter for %s]> ' "${default_spec:-nothing}" >&2
  read -r ans || return 2
  case "$ans" in
    '')
      printf '%s\n' "$default_spec"
      return 0
      ;;
    c | C)
      printf 'command> ' >&2
      read -r ans || return 2
      base=$(printf '%s' "$ans" | awk '{ print $1 }')
      if [ -z "$base" ] || ! command -v "$base" >/dev/null 2>&1; then
        echo "install: '$base' is not installed." >&2
        return 1
      fi
      printf '%s\n' "$ans"
      return 0
      ;;
    *[!0-9]*)
      echo "install: answer with a number, c, or Enter." >&2
      return 1
      ;;
  esac
  count=$(printf '%s\n' "$catalog" | grep -c .)
  if [ "$ans" -lt 1 ] || [ "$ans" -gt "$count" ]; then
    echo "install: no entry $ans (1 to $count)." >&2
    return 1
  fi
  line=$(printf '%s\n' "$catalog" | sed -n "${ans}p")
  base=$(printf '%s' "$line" | cut -d'|' -f2- | awk '{ print $1 }')
  if ! command -v "$base" >/dev/null 2>&1; then
    echo "install: $base is not installed; pick an installed tool or c for custom." >&2
    return 1
  fi
  printf '%s\n' "$(printf '%s' "$line" | cut -d'|' -f1)"
}

# set_ide_config KEY VALUE: store a pane default in the ide launcher's
# global config, preserving every other line already there. The ide launcher
# precedence is: flag > env > this file > builtins.
set_ide_config() {
  local key="$1" value="$2" tmp
  mkdir -p "$IDE_CONFIG_DIR"
  tmp="$IDE_CONFIG_DIR/.config.tmp.$$"
  if [ -f "$IDE_CONFIG_FILE" ]; then
    awk -F= -v k="$key" '$1 != k' "$IDE_CONFIG_FILE" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$IDE_CONFIG_FILE"
  echo "install: pane default $key=$value written to $IDE_CONFIG_FILE"
}

# choose_defaults: detect installed tools, report them, then honour flags or
# prompt per pane (only when stdin is a terminal and --no-pick was not
# given). Returns 2 when the user cancelled mid-prompt.
choose_defaults() {
  local spec status
  echo "install: installed harnesses detected: $(ready_harnesses "$(harnesses)")"
  if [ -n "$EDITOR_SPEC" ]; then
    resolve_spec "$EDITOR_SPEC" editor || return 1
    set_ide_config "EDITOR" "$EDITOR_SPEC"
  elif [ "$DO_PICK" -eq 1 ] && [ -t 0 ]; then
    spec=$(prompt_slot editor "editor for the left pane" "nvim") || return "$?"
    if [ -n "$spec" ]; then
      set_ide_config "EDITOR" "$spec"
    fi
  fi
  if [ -n "$TOP_SPEC" ]; then
    resolve_spec "$TOP_SPEC" harness || return 1
    set_ide_config "TOP" "$TOP_SPEC"
  elif [ "$DO_PICK" -eq 1 ] && [ -t 0 ]; then
    spec=$(prompt_slot harness "harness A for the top-right pane" "opencode") || return "$?"
    if [ -n "$spec" ]; then
      set_ide_config "TOP" "$spec"
    fi
  fi
  if [ -n "$BOTTOM_SPEC" ]; then
    resolve_spec "$BOTTOM_SPEC" harness || return 1
    set_ide_config "BOTTOM" "$BOTTOM_SPEC"
  elif [ "$DO_PICK" -eq 1 ] && [ -t 0 ]; then
    spec=$(prompt_slot harness "harness B for the bottom-right pane" "omp") || return "$?"
    if [ -n "$spec" ]; then
      set_ide_config "BOTTOM" "$spec"
    fi
  fi
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
  local status
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
      --no-pick) DO_PICK=0 ;;
      --editor)
        [ "$#" -ge 2 ] || { echo "install: --editor needs a value." >&2; return 1; }
        EDITOR_SPEC="$2"
        shift
        ;;
      --editor=*)
        EDITOR_SPEC="${1#--editor=}"
        ;;
      --top)
        [ "$#" -ge 2 ] || { echo "install: --top needs a value." >&2; return 1; }
        TOP_SPEC="$2"
        shift
        ;;
      --top=*)
        TOP_SPEC="${1#--top=}"
        ;;
      --bottom)
        [ "$#" -ge 2 ] || { echo "install: --bottom needs a value." >&2; return 1; }
        BOTTOM_SPEC="$2"
        shift
        ;;
      --bottom=*)
        BOTTOM_SPEC="${1#--bottom=}"
        ;;
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

  # 3) nvim config and user guide
  if [ "$DO_NVIM" -eq 1 ]; then
    install_file "$SOURCE_DIR/config/nvim/init.lua" "$NVIM_DIR/init.lua" ""
    install_file "$SOURCE_DIR/docs/neovim-guide.md" "$GUIDE_DIR/neovim-guide.md" ""
  fi

  # 4) pane defaults: detect installed tools, honour flags, ask on a TTY
  status=0
  choose_defaults || status=$?
  if [ "$status" -eq 2 ]; then
    echo "install: pane default selection cancelled; runtime defaults apply."
  elif [ "$status" -ne 0 ]; then
    return "$status"
  fi

  # 5) opencode config, skills, maintenance
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

  # 6) mlx extras
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
