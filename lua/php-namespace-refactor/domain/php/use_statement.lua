---@mod php-namespace-refactor.domain.php.use_statement Use statements
---
---Locating, building and injecting `use` statements. Nothing here touches a
---buffer or a file: injection returns a text edit for the caller to apply.

local M = {}

---A replacement of `text:sub(start + 1, finish)`: 0-based, end-exclusive
---byte offsets, so an insertion has `start == finish`.
---@class php_namespace_refactor.TextEdit
---@field start integer
---@field finish integer
---@field text string

---@class php_namespace_refactor.UseStatementLocation
---@field index integer 0-based byte offset where new statements go, 0 when there is no place for them
---@field is_first_use boolean The file has no `use` statement yet, `index` is the end of the namespace declaration

---Calls `fn(line, offset)` for each line, `offset` being the 0-based byte
---offset of the line start, until `fn` returns a non-nil value.
---@generic T
---@param text string
---@param fn fun(line: string, offset: integer): T?
---@return T?
local function each_line(text, fn)
  local pos = 1
  while pos <= #text do
    local line_end = text:find('\n', pos, true) or #text + 1
    local result = fn(text:sub(pos, line_end - 1), pos - 1)
    if result ~= nil then
      return result
    end
    pos = line_end + 1
  end
end

---End of the last line-leading `use ...;` statement.
---@param text string
---@return integer
local function last_use_end(text)
  local index = 0
  each_line(text, function(line, offset)
    -- Greedy, like /^use\s+[^\n]+;/: the statement ends at the line's last `;`.
    local semicolon = line:match('^use%s+.*();')
    if semicolon then
      index = offset + semicolon
    end
  end)
  return index
end

---End of the `namespace Foo\Bar;` declaration.
---@param text string
---@return integer
local function namespace_end(text)
  return each_line(text, function(line, offset)
    local semicolon = line:match('^%s*namespace%s+[A-Za-z0-9_\\]+();')
    if semicolon then
      return offset + semicolon
    end
  end) or 0
end

---Where new `use` statements go: after the last one, or after the namespace
---declaration when there is none.
---@param text string
---@return php_namespace_refactor.UseStatementLocation
function M.locate(text)
  local index = last_use_end(text)
  if index > 0 then
    return { index = index, is_first_use = false }
  end

  return { index = namespace_end(text), is_first_use = true }
end

---@param full_namespace string Fully qualified class name
---@return string statement Preceded by a newline, e.g. "\nuse App\\Foo;"
function M.statement(full_namespace)
  if full_namespace == '' then
    error('full_namespace must be a non-empty string', 2)
  end
  return ('\nuse %s;'):format(full_namespace)
end

---@param full_namespaces string[]
---@return string statements
function M.statements(full_namespaces)
  return table.concat(vim.tbl_map(M.statement, full_namespaces))
end

---Names imported by line-leading `use` statements.
---@param text string
---@return table<string, true>
local function imported_names(text)
  local imported = {}
  each_line(text, function(line)
    local name = line:match('^use%s+([A-Za-z0-9_\\]+)')
    if name then
      imported[name] = true
    end
  end)
  return imported
end

---Builds the edit that adds `statements` at `location`, skipping the ones
---the file already has. A file already covered by a `use` statement for a
---namespace must not get a duplicate appended: without this, touching the
---same directory across several separate renames/moves kept re-inserting
---the same import.
---@param text string
---@param location php_namespace_refactor.UseStatementLocation
---@param statements string As built by statement()/statements()
---@return php_namespace_refactor.TextEdit? edit nil when there is nothing to add
function M.inject(text, location, statements)
  local imported = imported_names(text)
  local missing = {}
  for name in statements:gmatch('use%s+([A-Za-z0-9_\\]+)%s*;') do
    if not imported[name] then
      imported[name] = true
      table.insert(missing, M.statement(name))
    end
  end

  if #missing == 0 then
    return nil
  end

  local new_statements = table.concat(missing)
  if not location.is_first_use then
    return { start = location.index, finish = location.index, text = new_statements }
  end

  -- The first statement gets a blank line on each side, replacing the
  -- newlines that followed the namespace declaration.
  local trailing_newlines = text:match('^\n*', location.index + 1)
  return {
    start = location.index,
    finish = location.index + #trailing_newlines,
    text = '\n\n' .. new_statements:gsub('^\n+', '') .. '\n\n',
  }
end

return M
