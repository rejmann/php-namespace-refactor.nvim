---@mod php-namespace-refactor.app.move Move command
---
---Moves a file or directory on disk, carries its loaded buffers along and
---refactors the project for it.

local file_move = require('php-namespace-refactor.app.operations.file_move')

local M = {}

---@param file string
---@return string
local function absolute(file)
  return (vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(file), ':p')):gsub('/+$', ''))
end

---Points the loaded buffers of `old` (a file, or anything under a
---directory) at their new path. Unmodified buffers are written to it right
---away, so Neovim treats them as editing that file and a later `:write`
---doesn't fail with E13.
---@param old string
---@param new string
local function rename_buffers(old, new)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    local target
    if name == old then
      target = new
    elseif vim.startswith(name, old .. '/') then
      target = new .. name:sub(#old + 1)
    end

    if target and vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_set_name(bufnr, target)
      if not vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd('silent! noautocmd write!')
        end)
      end
      -- nvim_buf_set_name() leaves an unlisted buffer behind for the old name.
      local stale = vim.fn.bufnr('^' .. vim.fn.fnameescape(name) .. '$')
      if stale ~= -1 and stale ~= bufnr and not vim.api.nvim_buf_is_loaded(stale) then
        vim.api.nvim_buf_delete(stale, { force = true })
      end
    end
  end
end

---@class php_namespace_refactor.MoveOpts
---@field on_done? fun() Called once the project has been refactored

---Moves `old` to `new` (a PHP file or a directory) and updates namespaces,
---class names, references and imports across the project. The refactor
---runs on the move queue, after the ones already queued.
---@param old string
---@param new string
---@param opts? php_namespace_refactor.MoveOpts
---@return boolean ok
---@return string? err
function M.move(old, new, opts)
  old, new = absolute(old), absolute(new)
  if old == new then
    return false, 'source and destination are the same'
  end
  if not vim.uv.fs_stat(old) then
    return false, ('%s does not exist'):format(old)
  end
  if vim.uv.fs_stat(new) then
    return false, ('%s already exists'):format(new)
  end

  vim.fn.mkdir(vim.fs.dirname(new), 'p')
  local ok, err = vim.uv.fs_rename(old, new)
  if not ok then
    return false, err
  end

  rename_buffers(old, new)
  file_move.enqueue({ { old = old, new = new } }, opts and opts.on_done)
  return true
end

---`:PhpNamespaceRefactor move [{old}] {new}`: with one argument, moves the
---current buffer's file.
---@param args string[]
function M.command(args)
  local old, new
  if #args == 1 then
    old, new = vim.api.nvim_buf_get_name(0), args[1]
  elseif #args == 2 then
    old, new = args[1], args[2]
  end

  if not old or old == '' then
    vim.notify('PhpNamespaceRefactor: usage: move [{old}] {new}', vim.log.levels.ERROR)
    return
  end

  local ok, err = M.move(old, new, {
    on_done = function()
      vim.notify(('PhpNamespaceRefactor: moved to %s'):format(vim.fn.fnamemodify(absolute(new), ':~:.')))
    end,
  })
  if not ok then
    vim.notify('PhpNamespaceRefactor: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

---@param arg_lead string Everything typed after `move `
---@return string[]
function M.complete(arg_lead)
  return vim.fn.getcompletion(arg_lead:match('%S*$'), 'file')
end

return M
