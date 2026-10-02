# ide-three-pane

A three-pane agentic IDE built on tmux, packaged for any macOS or Linux machine.

```
+---------------------+  +---------------------+
|                     |  |  harness A (top)    |
|   editor (nvim)     |  |  e.g. opencode      |
|                     |  +---------------------+
|                     |  |  harness B (bottom) |
|                     |  |  e.g. omp           |
+---------------------+  +---------------------+
```

One code editor on the left, two agent harnesses stacked on the right, in any
git repository. One tmux session per directory. Agents edit files on disk;
the editor pane shows those edits live and can diff any file against git
HEAD.

## What is included

| File | Installs to | Purpose |
| ---- | ----------- | ------- |
| `bin/ide` | `~/.local/bin/ide` | Session launcher. Per-directory tmux sessions, remembers tool choices, interactive `--pick` menu, project discovery under `$HOME`. |
| `bin/ide-focus` | `~/.local/bin/ide-focus` | Jump to a pane by role, number, or tool name. |
| `bin/ide-mouse` | `~/.local/bin/ide-mouse` | Toggle tmux mouse mode. |
| `config/tmux.conf` | `~/.tmux.conf` | Pane borders with titles, mouse support, vim-style pane binds, Alt+hjkl without prefix, base index 1. |
| `config/nvim/init.lua` | `~/.config/nvim/init.lua` | Editor pane: tmux-aware `<C-h/j/k/l>` navigation, live reload of agent edits, `:IdeDiff` review against git HEAD. |
| `opencode/opencode.jsonc` | `~/.config/opencode/opencode.jsonc` | Generated at install time. Cloudflare MCP servers always included; mlx provider only on Apple Silicon; persona-constitution and lummenna MCP servers only when their repositories exist under `$HOME`. |
| `opencode/skills/` | `~/.config/opencode/skills/` | 12 opencode skills (Cloudflare platform, wrangler, agents SDK, durable objects, and more). |
| `opencode/maintenance/compact-event-store.sh` | `~/.config/opencode/maintenance/` | Reclaims disk space in the opencode event store. Verifies integrity and projections before and after; refuses to run while opencode is running. |
| `extras/mlx/` | opt-in, see below | `mlx-serve` (local OpenAI-compatible inference server), `mlx-bench`, and the detokenizer fix helpers. Apple Silicon + MLX only. |

## Install

Clone and run the installer (recommended):

```sh
git clone https://github.com/QuantumindSSI/ide-three-pane.git
cd ide-three-pane
./install.sh
```

Or without cloning:

```sh
curl -fsSL https://github.com/QuantumindSSI/ide-three-pane/archive/refs/heads/main.tar.gz | tar -xz -C /tmp && bash /tmp/ide-three-pane-main/install.sh
```

The installer is idempotent. Files that would be overwritten and differ from
the packaged version are backed up to
`${XDG_DATA_HOME:-~/.local/share}/ide-three-pane/backups/<timestamp>/`.

### Options

| Flag | Effect |
| ---- | ------ |
| `--bin-dir DIR` | Install the bin scripts into DIR (default `~/.local/bin`). |
| `--with-mlx` | Also install the mlx extras. Requires an MLX venv at `~/.local/share/mlx-server/.venv` and an mlx-community model to be useful. |
| `--no-opencode` | Skip the opencode config, skills, and maintenance scripts. |
| `--no-nvim` | Skip the nvim config. |
| `--no-tmux` | Skip the tmux config. |
| `--no-path` | Never touch any shell rc file. |

The installer appends `~/.local/bin` to your PATH (zsh: `~/.zshrc`, bash:
`~/.bashrc`) only when it is missing, using a marked block you can delete.
Missing tmux, nvim, or opencode produce warnings with install hints, never
failures.

After installing: restart any running opencode so it reads the new config,
then `tmux source-file ~/.tmux.conf`, then open a project with `ide [dir]`.

## Usage

```sh
ide [dir]                # open the 3-pane session (remembered/default tools)
ide --pick [dir]         # choose editor + 2 harnesses interactively, remember
ide --editor SPEC --top SPEC --bottom SPEC [dir]
ide --forget [dir]       # forget remembered tools for a directory
ide --tools              # list known editors and harnesses
ide --list               # list every git repo discovered under ~
```

A SPEC is a catalog name (`nvim`, `hx`, `opencode`, `omp`, `claude`,
`codex`, `aider`, ...) or a full command such as `"aider --model sonnet"`.
Only terminal programs run inside a pane.

### Keys

| Key | Action |
| --- | ------ |
| mouse click | Focus any pane |
| `Ctrl-b` then `h/j/k/l` | Move focus directionally |
| `Ctrl-b` then `N` / `E` / `O` | Jump to editor / harness A / harness B |
| `Ctrl-b` then `m` | Toggle mouse mode |
| `Alt-h/j/k/l` | Same moves without prefix (macOS Terminal: enable "Use Option as Meta") |
| `ide-focus <tool\|1\|2\|3\|next>` | Jump from a shell or via `:!ide-focus opencode` in nvim |

### nvim extras

| Command | Action |
| ------- | ------ |
| `:IdeDiff` | Side-by-side diff of the current file against git HEAD |
| `:IdeDiffOff` | Close the diff view |
| `:IdeEditor` / `:IdeTop` / `:IdeBottom` | Jump to the other panes |
| `-` | Back out of a file into the directory listing |

Agent edits are re-read every second and on every pane re-entry, buffer
switch, or typing pause. Unsaved local edits are never clobbered.

## Machine-specific notes

- **opencode.jsonc is generated, not copied.** The installer includes the
  cloudflare and cloudflare-docs MCP servers always, the mlx provider only on
  Apple Silicon, and the persona-constitution and lummenna MCP servers only
  when `$HOME/mcp-servers/CTO-MCP` and `$HOME/lummenna` (each with a `.venv`)
  exist. Skipped blocks are reported during install; clone the repositories
  and re-run to enable them.
- **mlx extras** assume a venv at `~/.local/share/mlx-server/.venv` with
  `mlx-lm` installed, an mlx-community model under `~/.lmstudio/models`, and
  16GB or more of unified memory for 7B 4-bit models.
- **Skills** are copied as-is into `~/.config/opencode/skills/` and are
  picked up by opencode on its next start.

## Verify

```sh
./test.sh
```

Runs syntax checks, shellcheck, a full install into a temporary HOME, file
presence and permission checks, JSON validation of the generated config, an
`ide --tools` smoke test, an idempotency check, and an em dash scan. Exits 0
only when every check passes.

## Uninstall

Remove the installed files: `~/.local/bin/ide`, `~/.local/bin/ide-focus`,
`~/.local/bin/ide-mouse`, `~/.tmux.conf`, `~/.config/nvim/init.lua`,
`~/.config/opencode/`, and the PATH block in your shell rc. Restored
previous versions are in the backup directory the installer printed.
