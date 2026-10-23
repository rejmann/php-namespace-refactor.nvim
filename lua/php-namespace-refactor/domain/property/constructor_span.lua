---@mod php-namespace-refactor.domain.property.constructor_span Constructor span
---
---Port of ConstructorSpanFinder: where the `__construct` signature, its
---parameter list and its body are in a file. Offsets are 0-based bytes.

local M = {}

---@class php_namespace_refactor.ConstructorSpan
---@field constructor_start integer Start of `function __construct`
---@field params_start integer Just after the opening `(`
---@field params_end integer The closing `)`: `text:sub(params_start + 1, params_end)` is the parameter list
---@field body_start integer The opening `{` (or params_end + 1 for an abstract/interface constructor)
---@field body_end integer Just after the closing `}` (or the end of the text when it is unbalanced)

---0-based offset of the bracket closing the one at `open_index`.
---@param text string
---@param open_index integer 0-based offset of the opening bracket
---@param open string
---@param close string
---@return integer? close_index
function M.find_matching(text, open_index, open, close)
  local depth = 0
  for i = open_index + 1, #text do
    local char = text:sub(i, i)
    if char == open then
      depth = depth + 1
    elseif char == close then
      depth = depth - 1
      if depth == 0 then
        return i - 1
      end
    end
  end
  return nil
end

---@param text string
---@return php_namespace_refactor.ConstructorSpan?
function M.find(text)
  local s, e = text:find('function%s+__construct%s*%(')
  if not s or not e then
    return nil
  end

  local constructor_start = s - 1
  local params_start = e
  local params_end = M.find_matching(text, params_start - 1, '(', ')')
  if not params_end then
    return nil
  end

  local brace = text:find('{', params_end + 1, true)
  if not brace then
    return {
      constructor_start = constructor_start,
      params_start = params_start,
      params_end = params_end,
      body_start = params_end + 1,
      body_end = params_end + 1,
    }
  end

  local body_start = brace - 1
  local body_close = M.find_matching(text, body_start, '{', '}')

  return {
    constructor_start = constructor_start,
    params_start = params_start,
    params_end = params_end,
    body_start = body_start,
    body_end = body_close and body_close + 1 or #text,
  }
end

return M
