-- ide workstation config for the left editor pane.
-- Pane layout (tmux, pane-base-index 1): 1 = editor (this pane),
-- 2 = harness A (top right), 3 = harness B (bottom right).
-- The agent harnesses edit files on disk; everything below makes those
-- edits visible here live and gives quick keys to move between panes.

-- Mouse: click anywhere to move the cursor / focus splits,
-- matching the tmux mouse mode for panes.
vim.o.mouse = "a"

-- 1) Navigation -------------------------------------------------------------

local function tmux_move(win_cmd, tmux_dir)
  local before = vim.fn.winnr()
  vim.cmd("wincmd " .. win_cmd)
  if vim.fn.winnr() == before then
    vim.fn.system("tmux select-pane -" .. tmux_dir)
  end
end

local nav_opts = { noremap = true, silent = true, desc = "ide: move focus" }
vim.keymap.set("n", "<C-h>", function() tmux_move("h", "L") end, nav_opts)
vim.keymap.set("n", "<C-j>", function() tmux_move("j", "D") end, nav_opts)
vim.keymap.set("n", "<C-k>", function() tmux_move("k", "U") end, nav_opts)
vim.keymap.set("n", "<C-l>", function() tmux_move("l", "R") end, nav_opts)

vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { noremap = true, silent = true })
vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], { noremap = true, silent = true })
vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], { noremap = true, silent = true })
vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], { noremap = true, silent = true })

-- "-" backs out of a file into the directory listing (netrw).
vim.keymap.set("n", "-", "<cmd>Ex<cr>", { noremap = true, silent = true, desc = "ide: directory listing" })

-- Positional jumps to the other panes; legacy names kept working.
local function jump(index)
  vim.fn.system("tmux select-pane -t :." .. index)
end
vim.api.nvim_create_user_command("IdeEditor", function() jump(1) end, {})
vim.api.nvim_create_user_command("IdeTop", function() jump(2) end, {})
vim.api.nvim_create_user_command("IdeBottom", function() jump(3) end, {})
vim.api.nvim_create_user_command("IdeNvim", function() jump(1) end, {})
vim.api.nvim_create_user_command("IdeOpencode", function() jump(2) end, {})
vim.api.nvim_create_user_command("IdeOmp", function() jump(3) end, {})

-- 2) Live reload of agent edits ---------------------------------------------

vim.o.autoread = true
vim.o.updatetime = 500

-- Re-read every open, unmodified file that changed on disk.
-- Unsaved local edits are never clobbered: checktime refuses.
local function reload_changed_files()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf)
        and name ~= ""
        and vim.bo[buf].buftype == ""
        and vim.fn.isdirectory(name) ~= 1
        and not vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function() vim.cmd("checktime") end)
    end
  end
end

-- Refresh the netrw listing when the agents create or delete files,
-- keeping the cursor on the same entry.
local function refresh_dir_listing()
  if vim.bo.filetype ~= "netrw" then return end
  local dir = vim.b.netrw_curdir or vim.fn.expand("%:p")
  if dir == "" or vim.fn.isdirectory(dir) ~= 1 then return end
  local entries = vim.fn.readdir(dir)
  table.sort(entries)
  local snap = table.concat(entries, "\n")
  local prev = vim.b.ide_dir_snap
  vim.b.ide_dir_snap = snap
  if prev == nil or prev == snap then return end
  local line_text = vim.fn.getline(".")
  vim.cmd("keepalt silent! edit")
  if line_text ~= "" then
    vim.fn.search("\\V" .. vim.fn.escape(line_text, "\\"), "cW")
  end
end

-- One tick: re-read changed files, refresh the listing.
-- Skipped while typing, in cmdline, or in a terminal buffer so the
-- display never shifts under the user's fingers.
function _G.ide_live_tick()
  local m = vim.fn.mode()
  if m == "i" or m == "R" or m == "c" or m == "t" then return end
  reload_changed_files()
  refresh_dir_listing()
end

vim.fn.timer_start(1000, function() _G.ide_live_tick() end, { ["repeat"] = -1 })

-- Also reload instantly on pane re-entry, buffer switch, or typing pause.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  desc = "ide: show agent edits made on disk",
  callback = reload_changed_files,
})

-- 3) Review agent changes: :IdeDiff / :IdeDiffOff ----------------------------

local HEAD_PREFIX = "HEAD "

-- Open the current file side by side with its git HEAD version,
-- with vimdiff highlighting exactly what the agents changed.
vim.api.nvim_create_user_command("IdeDiff", function()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    vim.notify("IdeDiff: this buffer has no file", vim.log.levels.WARN)
    return
  end
  local ft = vim.bo.filetype
  local rel = vim.fn.fnamemodify(file, ":.")
  local head = vim.fn.systemlist({ "git", "show", "HEAD:./" .. rel })
  if vim.v.shell_error ~= 0 then
    vim.notify("IdeDiff: " .. file .. " has no version at HEAD (in a git repo?)", vim.log.levels.WARN)
    return
  end
  vim.cmd("rightbelow vnew")
  local scratch = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_set_name, scratch, HEAD_PREFIX .. rel)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].swapfile = false
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].modifiable = true
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, head)
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = ft
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
end, {})

-- Close the diff view and the scratch buffer.
vim.api.nvim_create_user_command("IdeDiffOff", function()
  vim.cmd("diffoff!")
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.startswith(name, HEAD_PREFIX) then
      vim.api.nvim_win_close(win, false)
    end
  end
end, {})

-- 4) User guide -------------------------------------------------------------

-- Open the bundled neovim user guide inside the editor pane.
-- Installed to ~/.local/share/ide-three-pane/docs/neovim-guide.md.
vim.api.nvim_create_user_command("IdeGuide", function()
  local guide = vim.fn.expand("~/.local/share/ide-three-pane/docs/neovim-guide.md")
  if vim.fn.filereadable(guide) ~= 1 then
    vim.notify("IdeGuide: guide not installed at " .. guide, vim.log.levels.WARN)
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(guide))
end, { desc = "ide: open the neovim user guide" })
