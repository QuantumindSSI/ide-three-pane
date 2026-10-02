# Neovim User Guide

The complete guide to using neovim as the editor pane of the ide-three-pane
workstation. It covers the four editing modes, every motion and operator you
need day to day, buffers, windows, tabs, search and replace, registers,
marks, the built-in file explorer, and the commands this specific setup adds
for working alongside agent harnesses.

No plugins are required. Everything here is stock neovim plus the small
`init.lua` this repo installs to `~/.config/nvim/init.lua`.

Open this guide from inside neovim at any time with `:IdeGuide`.

## 1. Survival card

Neovim is modal. Keys do different things depending on the current mode. If
anything ever feels wrong, press `Esc` twice: you are back in normal mode.

| Key | Mode you are in | What it does |
| --- | --------------- | ------------ |
| `i` | normal | Enter insert mode before the cursor; type text |
| `a` | normal | Enter insert mode after the cursor |
| `o` | normal | Open a new line below and enter insert mode |
| `Esc` | insert, visual, cmdline | Return to normal mode |
| `u` | normal | Undo |
| `Ctrl-r` | normal | Redo |
| `:w` | normal | Save (press Enter to run the command) |
| `:q` | normal | Quit |
| `:wq` or `ZZ` | normal | Save and quit |
| `:q!` | normal | Quit without saving |
| `:e!` | normal | Reload the file from disk, discarding local edits |

Write that last column down mentally: `Esc Esc`, `u`, `:w`, `:q!`. With those
four you cannot lose work or get stuck.

## 2. Modes

| Mode | Enter with | Purpose |
| ---- | ---------- | ------- |
| normal | `Esc` | Navigate, delete, copy, run commands. The home mode. |
| insert | `i`, `a`, `o`, `I`, `A`, `O` | Type text like a normal editor |
| replace | `R` | Overwrite existing characters as you type |
| visual | `v` | Select characters, then operate on them |
| visual line | `V` | Select whole lines |
| visual block | `Ctrl-v` | Select a rectangle, e.g. a column |
| command-line | `:` | Run ex commands: `:w`, `:s`, `:e` |
| terminal | `:terminal` | A shell inside a window; `Esc` returns to normal |

The command-line prompt at the bottom shows `:` in normal mode, `/` for
search, and `?` for reverse search. Press `Esc` to cancel any of them.

## 3. Moving around

Motions are how you move in normal mode. A number before a motion repeats it:
`3w` moves three words, `5j` moves five lines down.

### Within the line

| Key | Action |
| --- | ------ |
| `h` `l` | One character left / right |
| `0` | Start of line |
| `^` | First non-blank character of the line |
| `$` | End of line |
| `g_` | Last non-blank character of the line |
| `f` + char | Jump forward to char, e.g. `f(` jumps to the next `(` |
| `F` + char | Same, backwards |
| `t` + char | Jump forward to just before char (till) |
| `T` + char | Same, backwards |
| `;` | Repeat the last `f`/`t`/`F`/`T` |
| `,` | Repeat it in the opposite direction |
| `%` | Jump to the matching bracket: `()`, `[]`, `{}` |

### Across lines and the file

| Key | Action |
| --- | ------ |
| `j` `k` | One line down / up |
| `w` `b` | Next / previous word start |
| `e` `ge` | Next / previous word end |
| `W` `B` `E` | Same, but words are whitespace-separated only |
| `{` `}` | Previous / next blank line (paragraph) |
| `gg` | Top of file |
| `G` | Bottom of file |
| `123G` or `:123` | Line 123 |
| `ggVG` | Select the whole file |

### Scrolling

| Key | Action |
| --- | ------ |
| `Ctrl-f` / `Ctrl-b` | Page down / up |
| `Ctrl-d` / `Ctrl-u` | Half page down / up |
| `zz` `zt` `zb` | Center / top / bottom the current line on screen |
| `Ctrl-e` / `Ctrl-y` | Scroll one line down / up |

### Precise word moves

`w` stops at punctuation, `W` does not. In `foo.bar_baz`, `w` lands on `.`,
then `bar_baz`; `W` lands directly on `bar_baz`. Use the capital forms for
camelCase and snake_case code, the lowercase forms for prose.

## 4. Editing text

### Entering insert mode

| Key | Action |
| --- | ------ |
| `i` / `a` | Insert before / after the cursor |
| `I` / `A` | Insert at first / last non-blank of the line |
| `o` / `O` | New line below / above |
| `gi` | Insert where you last left insert mode |

### Deleting

Deletions copy into the unnamed register, so `dd` then `p` moves a line.

| Key | Action |
| --- | ------ |
| `x` / `X` | Delete character under / before the cursor |
| `dd` | Delete (cut) the whole line |
| `D` | Delete to end of line |
| `dw` `dW` | Delete a word |
| `d$` or `D` | Delete to end of line |
| `d0` | Delete to start of line |
| `dG` | Delete to end of file |
| `dgg` | Delete to top of file |
| `diw` | Delete inner word: the word under the cursor, no spaces |
| `daw` | Delete a word plus one adjacent space |
| `di(` `da(` | Delete inside / around parentheses |
| `di"` `da"` | Delete inside / around double quotes |
| `di{` `da{` | Delete inside / around braces |
| `3dd` | Delete 3 lines |

### Change, yank, put

The pattern is: operator + motion. `d` deletes, `c` deletes and enters
insert mode, `y` copies (yanks). Text objects (`iw`, `aw`, `i(`, `a(`, `i"`,
`a"`, `it`, `at`) work after any of them.

| Key | Action |
| --- | ------ |
| `cw` | Change word: delete it and start typing |
| `cc` or `S` | Change the whole line |
| `C` | Change to end of line |
| `ciw` | Change inner word |
| `ci(` | Change inside parentheses: retyping function arguments |
| `ci"` | Change inside quotes: retyping a string |
| `yy` | Yank (copy) the whole line |
| `yw` `yiw` | Yank a word |
| `y$` | Yank to end of line |
| `p` / `P` | Put after / before the cursor |
| `J` | Join the next line onto this one with a space |
| `gJ` | Join without a space |
| `r` + char | Replace one character |
| `R` | Enter replace mode |
| `~` | Toggle case of the character under the cursor |
| `gUU` | Uppercase the whole line |
| `guu` | Lowercase the whole line |
| `>` `>>` | Indent motion / line (in normal mode) |
| `<` `<<` | Dedent motion / line |
| `.` | Repeat the last change. Press `n` then `.` to repeat a fix on every match |

`ci(` is the single most useful editing key for code: put the cursor anywhere
inside the parentheses and retype everything between them.

## 5. Search and replace

### Searching in the file

| Key | Action |
| --- | ------ |
| `/pattern` | Search forward, Enter to go |
| `?pattern` | Search backward |
| `n` / `N` | Next / previous match, same direction as the search |
| `*` | Search for the word under the cursor, forward |
| `#` | Same, backward |
| `:noh` | Clear the search highlighting until the next search |

Searches accept regular expressions. Useful atoms: `.` any character, `\d`
digit, `\w` word character, `\s` whitespace, `^` line start, `$` line end,
`\<` `\>` word boundaries, `[abc]` character class, `\v` "very magic" mode
where most punctuation needs no escaping.

Example: `/\vfunction\s+\w+` finds a function definition with exactly one
space after the keyword.

### Replacing

| Command | Effect |
| ------- | ------ |
| `:s/old/new/` | Replace the first `old` on the current line |
| `:s/old/new/g` | Replace every `old` on the current line |
| `:%s/old/new/g` | Replace every `old` in the file |
| `:%s/old/new/gc` | Same, but confirm each match: `y` yes, `n` no, `a` all, `q` quit |
| `:%s/old/new/gi` | Case-insensitive |
| `:'<,'>s/old/new/g` | Only inside the visual selection (press `V`, select, then `:`) |
| `:%s/^/  /` | Prefix every line with two spaces |
| `:%s/$/;/` | Suffix every line with a semicolon |
| `:%s/\v(old)/\U\1/g` | Uppercase every match |

In the replacement, `&` is the whole match, `\0` the same, `\1` to `\9` are
captured groups, `\U` uppercases what follows, `\L` lowercases it. Example:
`:s/\v\<(\w+)\>/\U\1\E/g` uppercases every word on the line.

`:%s/old/new/gc` with confirm is the safe habit when editing shared code.

## 6. Undo, redo, repeat

| Key | Action |
| --- | ------ |
| `u` | Undo one change |
| `U` | Undo all latest changes on one line |
| `Ctrl-r` | Redo |
| `5u` | Undo 5 changes |
| `:undolist` | List undo branches |
| `:earlier 5m` | Go back to how the file was 5 minutes ago |
| `:later 5m` | Go forward again |
| `g;` / `g,` | Jump to older / newer position in the change list |
| `.` | Repeat the last change at the cursor |

`:earlier`/`:later` work even across saves, which makes them a safety net
when an agent rewrote a file while you were away.

## 7. Buffers, windows, tabs

A buffer is a file in memory. A window is a viewport on a buffer. A tab page
is a layout of windows. You will mostly use buffers and windows.

### Buffers

| Key | Action |
| --- | ------ |
| `:ls` | List all buffers |
| `:b filename` | Go to the buffer matching filename (Tab completes) |
| `:bn` / `:bp` | Next / previous buffer |
| `:b#` | Previous buffer (toggle) |
| `Ctrl-^` | Toggle between the current and the alternate buffer |
| `:bd` | Close the current buffer |
| `:bufdo :e` | Reload every buffer from disk |

This setup opens one buffer per file the agents touch, so `:ls` and `:b`
become your file switcher. `:b exa` + Tab jumps to any file with "exa" in
the name.

### Windows (splits)

| Key | Action |
| --- | ------ |
| `Ctrl-w s` | Split horizontally |
| `Ctrl-w v` | Split vertically |
| `Ctrl-w h/j/k/l` | Move between windows |
| `Ctrl-w o` | Close every window except the current one |
| `Ctrl-w c` | Close the current window |
| `Ctrl-w =` | Make all windows equal size |
| `Ctrl-w _` / `Ctrl-w |` | Maximize height / width |
| `Ctrl-w +/-` | Grow / shrink height |
| `Ctrl-w >/<` | Grow / shrink width |
| `Ctrl-w r` | Rotate windows |
| `Ctrl-w x` | Exchange windows |

In this setup you do not need `Ctrl-w h/j/k/l`: plain `Ctrl-h/j/k/l` moves
between neovim windows AND tmux panes, so the same keys land you in the
opencode or omp pane. See section 12.

### Tabs

| Key | Action |
| --- | ------ |
| `:tabnew [file]` | New tab page |
| `gt` / `gT` | Next / previous tab |
| `3gt` | Tab 3 |
| `:tabclose` | Close the tab |

Tabs are layouts of windows; use them for whole contexts, not files.

## 8. Visual mode

| Key | Action |
| --- | ------ |
| `v` | Character-wise visual |
| `V` | Line-wise visual |
| `Ctrl-v` | Block-wise visual (rectangle) |
| `o` | Jump to the other end of the selection |
| `O` | Block-wise: jump to the other corner on the same line |
| `gv` | Re-select the last visual selection |
| `aw` `iw` | Extend selection to a word |
| `u` / `U` | Lowercase / uppercase the selection |
| `J` | Join the selected lines |
| `>` / `<` | Indent / dedent the selection, keep selection with `gv` |
| `:` | Run a command on the selection, e.g. `:'<,'>s/old/new/g` |
| `I` | Block-wise: insert at the start of every selected line, `Esc` to apply |
| `A` | Block-wise: append at the end of every selected line, `Esc` to apply |
| `c` | Change the selection |
| `d` / `x` | Delete the selection |

Block-wise `I` and `A` are how you prefix or suffix a column of lines in one
stroke: `Ctrl-v`, select down with `3j`, `I#`, `Esc` comments out four lines.

## 9. Registers and the clipboard

Every delete and yank lands in a register. `"` then a letter or digit names
one.

| Key | Action |
| --- | ------ |
| `"ayy` | Yank the line into register a |
| `"ap` | Put from register a |
| `"0p` | Put from the yank register (survives later deletes) |
| `"+p` | Put from the system clipboard |
| `"+yy` | Yank the line into the system clipboard |
| `:reg` | Show every register |
| `"_dd` | Delete into the blackhole register: destroys, does not clobber |

The numbered registers `"1` to `"9` hold the last nine deletes, newest
first. The unnamed register `""` is what a plain `p` uses.

Copy a function to the clipboard: put the cursor on it, `V`, `}` to extend
to the end of the block, `"+y`. Paste from the clipboard into insert mode
with `Ctrl-r +`.

## 10. Marks and jumps

| Key | Action |
| --- | ------ |
| `ma` | Set mark a at the cursor |
| `'a` | Jump to the line of mark a |
| `` `a `` | Jump to the exact position of mark a |
| `` `` `` | Jump back to where you were before the last jump |
| `''` | Jump back to the line before the last jump |
| `Ctrl-o` / `Ctrl-i` | Older / newer position in the jump list |
| `` `. `` | Position of the last change |
| `g;` | Position of the last edited line |

Uppercase marks (`mA`) are global across files. The jump list remembers your
last 100 positions, so `Ctrl-o Ctrl-o` walks back through where you have
been.

## 11. The file explorer (netrw)

This setup binds `-` to open the directory of the current file with netrw,
neovim's built-in explorer.

| Key | In netrw | Action |
| --- | -------- | ------ |
| `-` | anywhere | Open the explorer on the current directory |
| `Enter` | on a file | Open the file |
| `-` | on a directory | Go up one level |
| `%` | anywhere | Create a new file |
| `d` | anywhere | Create a new directory |
| `D` | on an entry | Delete it (asks to confirm) |
| `R` | on an entry | Rename it |
| `I` | anywhere | Toggle the directory header |
| `i` | anywhere | Cycle the listing style: thin, long, wide, tree |
| `s` | anywhere | Cycle sort order: name, time, size |
| `:Ex` | anywhere | Open the explorer again |
| `:Lexplore` | anywhere | Explorer in a fixed vertical window |

The explorer is how you watch agent work at the file level: new files agents
create appear in the listing, refreshed every second by this setup's live
tick.

## 12. This setup: pane navigation and live reload

The workstation is one tmux session: editor left (pane 1), harness A
top-right (pane 2), harness B bottom-right (pane 3). Agents edit files on
disk; everything below keeps this pane in sync with them.

### Keys this config binds

| Key | Action |
| --- | ------ |
| `Ctrl-h/j/k/l` | Move focus between neovim windows; when at the edge, into the adjacent tmux pane |
| `Ctrl-h/j/k/l` in terminal mode | Leave terminal mode, then move as above |
| `-` | Open the netrw directory listing |
| mouse click | Move the cursor and focus splits, matching tmux mouse mode |

The tmux side adds, with the `Ctrl-b` prefix: `h/j/k/l` directional,
`N`/`E`/`O` jumps to panes 1/2/3, `m` toggles mouse mode. Without the
prefix, `Alt-h/j/k/l` does the same moves. From a shell or via `:!` you can
run `ide-focus opencode` to jump by tool name.

### Commands this config adds

| Command | Action |
| --- | ------ |
| `:IdeDiff` | Diff the current file against its git HEAD, side by side |
| `:IdeDiffOff` | Close the diff view |
| `:IdeEditor` | Jump to pane 1 |
| `:IdeTop` | Jump to pane 2 |
| `:IdeBottom` | Jump to pane 3 |
| `:IdeNvim` / `:IdeOpencode` / `:IdeOmp` | Same jumps, by tool name |
| `:IdeGuide` | Open this guide |

### How live reload works

Every second, and on every pane re-entry, buffer switch, or typing pause,
this setup:

1. Re-reads every open, unmodified buffer that changed on disk. Unsaved
   local edits are never clobbered: `checktime` refuses.
2. Refreshes the netrw listing when files are created or deleted, keeping
   the cursor on the same entry.

The tick skips insert mode, replace mode, command-line mode, and terminal
buffers, so the display never shifts while you are typing.

## 13. Reviewing agent edits

The core workflow of the workstation: agents (opencode, omp, hermes, codex)
edit files in the right panes; you review in this one.

1. **See what changed.** Stay in the editor pane. Changes agents made appear
   live; the netrw listing shows files they created or deleted.
2. **Inspect the diff.** Open the file, run `:IdeDiff`. The left window is
   the file at git HEAD, the right is the working copy, with every change
   highlighted. Close with `:IdeDiffOff`.
3. **Accept or reject per hunk with git.** `git diff` in any shell to see it
   in the terminal, `git add -p` to stage selected hunks, or
   `git checkout -- file` to throw a file's changes away entirely.
4. **Loop.** Jump to a harness pane with `Ctrl-l` (twice: first to the
   top-right pane, then within it), tell the agent what to fix, come back
   with `Ctrl-h`.

`:IdeDiff` compares against HEAD, so it shows everything since the last
commit, yours and the agents'. Commit early to get clean review points.

## 14. Searching across files

The `:vim` (vimgrep) command searches a file list, the quickfix window shows
results.

| Command | Effect |
| ------- | ------ |
| `:vim /pattern/gj **/*.py` | Search all Python files recursively |
| `:vim /pattern/gj **/*.{ts,tsx}` | Search two extensions |
| `:copen` | Open the quickfix window with the matches |
| `:cn` / `:cp` | Next / previous match |
| `:cclose` | Close the quickfix window |
| `:cfirst` / `:clast` | First / last match |
| `Ctrl-w Enter` (in quickfix) | Open the match in a split |

The `j` flag keeps vimgrep from jumping straight to the first match. Typical
flow: `:vim /IdeDiff/gj **/*.lua | copen`, walk the matches with `:cn`.

## 15. Getting help

| Key | Action |
| --- | ------ |
| `:help` | The help system home |
| `:help x` | Help for a key, e.g. `:help ci(`, `:help Ctrl-w` |
| `:help :s` | Help for an ex command |
| `:help 'option'` | Help for an option, e.g. `:help 'autoread'` |
| `:help i_CTRL-R` | Help for a key in a specific mode |
| `:help user-manual` | The full user manual, chapter list |
| `:help index` | Every default mapping |
| `:Tutor` | The 30-minute interactive tutorial |
| `:checkhealth` | Report on the neovim installation |
| `:version` | Version and build info |

Help windows are normal windows: `Ctrl-w o` to maximize, `:q` to close.
Search inside help with the usual `/`.

## 16. Customising the config

The config lives at `~/.config/nvim/init.lua`. It is plain Lua: `vim.o.x =
"y"` sets an option, `vim.keymap.set` adds a mapping, and
`vim.api.nvim_create_user_command` adds a command.

Reload after editing it with `:source ~/.config/nvim/init.lua`, or restart
neovim for a clean state. Changes take effect in the running instance only
after the reload; new instances read the file at startup.

Useful additions that fit the existing style:

```lua
-- Relative line numbers for counts that scale with distance.
vim.o.relativenumber = true

-- Highlight the cursor's screen line.
vim.o.cursorline = true

-- Keep the visible context when wrapping.
vim.o.breakindent = true
```

Set options permanently by putting them in the file; set them for one
session only with the same `vim.o.x = "y"` typed on the command line as
`:lua vim.o.relativenumber = true`.

The installed copy of this guide lives at
`~/.local/share/ide-three-pane/docs/neovim-guide.md`; reinstalling the repo
refreshes it.
