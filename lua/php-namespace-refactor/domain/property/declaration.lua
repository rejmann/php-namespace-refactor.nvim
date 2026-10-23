---@mod php-namespace-refactor.domain.property.declaration Property declaration
---
---Port of buildPropertyDeclarationPattern: finds a class-body property
---declaration for `$var_name` - e.g. `private Test $test;` or, since the
---type hint is optional in PHP, a legacy `private $test;` typed only via a
---`@var Test` docblock. The class name is accepted but not required, so a
---property whose type was never declared in code (only documented) is
---still found once the caller has already confirmed by other means (e.g. a
---constructor assignment) that it holds an instance of that class.

local M = {}

M.VISIBILITIES = { 'public', 'protected', 'private' }

---@param char string
---@return boolean
local function is_word_char(char)
  return char:find('^[A-Za-z0-9_]$') ~= nil
end

---Matches `$var_name\s*;` at `pos`.
---@param text string
---@param pos integer
---@param var_name string
---@return integer? after 1-based position after the `;`
local function match_variable(text, pos, var_name)
  return text:match('^%$' .. vim.pesc(var_name) .. '%s*;()', pos)
end

---Matches what follows the visibility keyword at `pos`:
---`\s+(readonly\s+)?(\??Class\s+)?\$var\s*;`
---@param text string
---@param pos integer
---@param class_name string
---@param var_name string
---@return integer? after
local function match_rest(text, pos, class_name, var_name)
  pos = text:match('^%s+()', pos)
  if not pos then
    return nil
  end
  pos = text:match('^readonly%s+()', pos) or pos

  local type_start = text:match('^%??()', pos)
  local type_end = text:match('^' .. vim.pesc(class_name) .. '()', type_start)
  if type_end and not is_word_char(text:sub(type_end, type_end)) then
    local after_type = text:match('^%s+()', type_end)
    local after = after_type and match_variable(text, after_type, var_name)
    if after then
      return after
    end
  end

  return match_variable(text, pos, var_name)
end

---First declaration of the property in `text`.
---@param text string
---@param class_name string
---@param var_name string Property name, without `$`
---@return integer? start 0-based offset of the visibility keyword
---@return integer? finish 0-based, end-exclusive offset (after the `;`)
function M.find(text, class_name, var_name)
  local best_start, best_finish

  for _, visibility in ipairs(M.VISIBILITIES) do
    local init = 1
    while true do
      local s, e = text:find(visibility, init, true)
      if not s or (best_start and s > best_start) then
        break
      end
      local after = match_rest(text, e + 1, class_name, var_name)
      if after then
        best_start, best_finish = s, after - 1
        break
      end
      init = s + 1
    end
  end

  if not best_start then
    return nil
  end
  return best_start - 1, best_finish
end

return M
