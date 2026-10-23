---@mod php-namespace-refactor.app.services.directory_moved_files_resolver Directory move expansion
---
---Port of DirectoryMovedFilesResolver: a moved directory becomes one move
---per file inside it.

local M = {}

---@class php_namespace_refactor.FileMove
---@field old string Path before the move
---@field new string Path after the move

---@param file string
---@return boolean
local function is_directory(file)
  local stat = vim.uv.fs_stat(file)
  return stat ~= nil and stat.type == 'directory'
end

---Moves of every file under the (already moved) directory `move.new`.
---@param move php_namespace_refactor.FileMove
---@return php_namespace_refactor.FileMove[]
local function from_directory(move)
  local moves = {}
  for name, type in vim.fs.dir(move.new, { depth = math.huge }) do
    if type == 'file' then
      table.insert(moves, { old = move.old .. '/' .. name, new = move.new .. '/' .. name })
    end
  end
  table.sort(moves, function(a, b)
    return a.new < b.new
  end)
  return moves
end

---Moves of the loaded buffers under `move.new`, for a directory whose new
---location can't be listed (yet).
---@param move php_namespace_refactor.FileMove
---@return php_namespace_refactor.FileMove[]
local function from_buffers(move)
  local moves = {}
  local prefix = move.new .. '/'
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ''
    if vim.startswith(name, prefix) then
      table.insert(moves, { old = move.old .. '/' .. name:sub(#prefix + 1), new = name })
    end
  end
  return moves
end

---@param file string
---@return boolean
local function has_extension(file)
  return vim.fs.basename(file):find('.', 2, true) ~= nil
end

---Expands directory moves into file moves, keeping file moves as they are.
---@param moves php_namespace_refactor.FileMove[]
---@return php_namespace_refactor.FileMove[]
function M.execute(moves)
  local result = {}
  local seen = {}

  local function add(move)
    local key = move.old .. '\0' .. move.new
    if not seen[key] then
      seen[key] = true
      table.insert(result, move)
    end
  end

  for _, move in ipairs(moves) do
    local expanded
    if is_directory(move.new) then
      expanded = from_directory(move)
    elseif not has_extension(move.old) and not has_extension(move.new) then
      expanded = from_buffers(move)
      if #expanded == 0 then
        expanded = { move }
      end
    else
      expanded = { move }
    end
    vim.iter(expanded):each(add)
  end

  return result
end

return M
