---@mod php-namespace-refactor.infra.edit Workspace edits
---
---Collects text edits for several files and applies them, the counterpart of
---a VS Code WorkspaceEdit. Offsets are bytes of the text returned by
---`fs.read_text()`, so edits must be computed from that same text.
---
---Loaded buffers are changed in place with a single nvim_buf_set_text() call
---(one undo step per buffer, left unsaved). Other files are written straight
---to disk, or loaded into a listed buffer and left unsaved when
---`edit_files_in_background` is off. There is no multi-file undo.

local fs = require('php-namespace-refactor.infra.fs')

local M = {}

---@class php_namespace_refactor.WorkspaceEdit
---@field private files table<string, php_namespace_refactor.TextEdit[]>
---@field private order string[]
local WorkspaceEdit = {}
WorkspaceEdit.__index = WorkspaceEdit

---@return php_namespace_refactor.WorkspaceEdit
function M.new()
  return setmetatable({ files = {}, order = {} }, WorkspaceEdit)
end

---Adds an edit to `path`. Edits at the same offset are applied in the order
---they were added.
---@param path string
---@param edit php_namespace_refactor.TextEdit
function WorkspaceEdit:add(path, edit)
  if not self.files[path] then
    self.files[path] = {}
    table.insert(self.order, path)
  end
  table.insert(self.files[path], edit)
end

---@param path string
---@param start integer 0-based byte offset
---@param finish integer 0-based, end-exclusive byte offset
---@param text string
function WorkspaceEdit:replace(path, start, finish, text)
  self:add(path, { start = start, finish = finish, text = text })
end

---@param path string
---@param offset integer 0-based byte offset
---@param text string
function WorkspaceEdit:insert(path, offset, text)
  self:add(path, { start = offset, finish = offset, text = text })
end

---@return string[] paths In the order they were first edited
function WorkspaceEdit:paths()
  return vim.list_extend({}, self.order)
end

---@param path string
---@return php_namespace_refactor.TextEdit[]
function WorkspaceEdit:edits(path)
  return self.files[path] or {}
end

---@return boolean
function WorkspaceEdit:is_empty()
  return #self.order == 0
end

---Applies `edits` to `text`.
---@param text string
---@param edits php_namespace_refactor.TextEdit[]
---@return string? text
---@return string? err When edits overlap or fall outside the text
function M.apply_to_text(text, edits)
  local sorted = {}
  for i, edit in ipairs(edits) do
    sorted[i] = { edit = edit, index = i }
  end
  table.sort(sorted, function(a, b)
    if a.edit.start ~= b.edit.start then
      return a.edit.start < b.edit.start
    end
    return a.index < b.index
  end)

  local parts = {}
  local last = 0
  for _, item in ipairs(sorted) do
    local edit = item.edit
    if edit.start < last or edit.finish < edit.start or edit.finish > #text then
      return nil, ('invalid or overlapping edit at %d-%d'):format(edit.start, edit.finish)
    end
    table.insert(parts, text:sub(last + 1, edit.start))
    table.insert(parts, edit.text)
    last = edit.finish
  end
  table.insert(parts, text:sub(last + 1))

  return table.concat(parts)
end

---0-based (row, col) of a byte offset in `lines`.
---@param lines string[]
---@param offset integer
---@return integer row
---@return integer col
local function position(lines, offset)
  local line_start = 0
  for i, line in ipairs(lines) do
    if offset <= line_start + #line then
      return i - 1, offset - line_start
    end
    line_start = line_start + #line + 1
  end
  return #lines - 1, #lines[#lines]
end

---Replaces the part of the buffer that differs between `old` and `new` with
---a single nvim_buf_set_text(), keeping marks and the cursor elsewhere intact
---and making the whole change one undo step.
---@param bufnr integer
---@param old string Current buffer text, as returned by fs.buffer_text()
---@param new string
local function set_buffer_text(bufnr, old, new)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local body = table.concat(lines, '\n')
  -- fs.buffer_text() appends the end-of-line newline, which isn't buffer content.
  if #old > #body then
    if new:sub(-1) == '\n' then
      new = new:sub(1, -2)
    else
      vim.bo[bufnr].eol = false
      vim.bo[bufnr].fixeol = false
    end
  end

  if body == new then
    return
  end

  local prefix = 0
  local max_prefix = math.min(#body, #new)
  while prefix < max_prefix and body:byte(prefix + 1) == new:byte(prefix + 1) do
    prefix = prefix + 1
  end

  local suffix = 0
  local max_suffix = math.min(#body, #new) - prefix
  while suffix < max_suffix and body:byte(#body - suffix) == new:byte(#new - suffix) do
    suffix = suffix + 1
  end

  local start_row, start_col = position(lines, prefix)
  local end_row, end_col = position(lines, #body - suffix)
  local replacement = vim.split(new:sub(prefix + 1, #new - suffix), '\n', { plain = true })
  vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, replacement)
end

---@class php_namespace_refactor.ApplyOpts
---@field background? boolean Write files that aren't loaded to disk (default: `edit_files_in_background`). When false they are loaded into listed buffers and left unsaved.

---@class php_namespace_refactor.ApplyResult
---@field changed string[] Paths whose contents changed
---@field errors table<string, string> Paths that couldn't be edited, with the reason

---Applies every collected edit.
---@param opts? php_namespace_refactor.ApplyOpts
---@return php_namespace_refactor.ApplyResult
function WorkspaceEdit:apply(opts)
  local background = opts and opts.background
  if background == nil then
    background = require('php-namespace-refactor.config').get().edit_files_in_background
  end

  local result = { changed = {}, errors = {} }

  for _, path in ipairs(self.order) do
    local bufnr = fs.find_buffer(path)
    if not bufnr and not background then
      bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(bufnr)
      vim.bo[bufnr].buflisted = true
    end

    local old, read_err
    if bufnr then
      old = fs.buffer_text(bufnr)
    else
      old, read_err = fs.read_file(path)
    end

    local new, err = nil, read_err
    if old then
      new, err = M.apply_to_text(old, self.files[path])
    end

    if not old or not new then
      result.errors[path] = err or 'unknown error'
    elseif new ~= old then
      if bufnr then
        set_buffer_text(bufnr, old, new)
      else
        local ok, write_err = fs.write_file(path, new)
        if not ok then
          result.errors[path] = write_err or 'write failed'
        end
      end
      if not result.errors[path] then
        table.insert(result.changed, path)
      end
    end
  end

  return result
end

return M
