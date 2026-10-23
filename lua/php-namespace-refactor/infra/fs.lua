---@mod php-namespace-refactor.infra.fs File access
---
---Reads and writes file contents, preferring a loaded buffer over the disk
---so unsaved changes are what gets refactored.

local M = {}

---@param path string
---@return string
local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

---Loaded buffer showing `path`, if any.
---@param path string
---@return integer? bufnr
function M.find_buffer(path)
  local target = normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name ~= '' and normalize(name) == target then
        return bufnr
      end
    end
  end
  return nil
end

---Buffer contents as a single string, with a trailing newline when the file
---would be written with one.
---@param bufnr integer
---@return string
function M.buffer_text(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, '\n')
  local eol = vim.bo[bufnr].eol or vim.bo[bufnr].fixeol
  if eol and not (#lines == 1 and lines[1] == '') then
    text = text .. '\n'
  end
  return text
end

---@param path string
---@return string? text
---@return string? err
function M.read_file(path)
  local file, err = io.open(path, 'rb')
  if not file then
    return nil, err
  end
  local text = file:read('*a')
  file:close()
  return text
end

---@param path string
---@param text string
---@return boolean ok
---@return string? err
function M.write_file(path, text)
  local file, err = io.open(path, 'wb')
  if not file then
    return false, err
  end
  file:write(text)
  file:close()
  return true
end

---Contents of `path`: the loaded buffer's when there is one, otherwise the
---file on disk.
---@param path string
---@return string? text
---@return string? err
function M.read_text(path)
  local bufnr = M.find_buffer(path)
  if bufnr then
    return M.buffer_text(bufnr)
  end
  return M.read_file(path)
end

return M
