---@mod php-namespace-refactor.domain.php.patterns PHP patterns
---
---Plain-text matching of PHP identifiers and declarations. JS regex
---lookarounds have no Lua pattern equivalent, so identifiers are found with a
---plain `string.find` plus a check of the neighboring bytes.

local M = {}

M.DECLARATION_MODIFIERS = { 'abstract', 'final' }

M.NAMED_TYPE_KEYWORDS = { 'class', 'interface', 'trait', 'enum' }

---A namespace/identifier boundary: neither an identifier character (letter,
---digit, underscore) nor a namespace separator (\) can sit on either side of
---a match, otherwise the match is actually a prefix or suffix of a longer FQCN
---rather than the identifier itself - e.g. matching "Foo" inside "FooBar" or
---inside "Foo\Bar\Baz" (a sub-namespace that merely starts with "Foo").
---@param char string A single byte, or '' outside the text
---@return boolean
function M.is_namespace_char(char)
  return char:find('^[A-Za-z0-9_\\]$') ~= nil
end

---@class php_namespace_refactor.FindOpts
---@field left_boundary? boolean Require a boundary before the match too (default true). Disable it to match a namespace inside a longer, leading-backslash FQCN.

---Finds every occurrence of `needle` not followed (and, by default, not
---preceded) by a namespace character.
---@param text string
---@param needle string
---@param opts? php_namespace_refactor.FindOpts
---@return [integer, integer][] ranges 1-based, inclusive byte ranges
function M.find_all(text, needle, opts)
  local left_boundary = not opts or opts.left_boundary ~= false
  local ranges = {}
  if needle == '' then
    return ranges
  end

  local init = 1
  while true do
    local s, e = text:find(needle, init, true)
    if not s then
      break
    end

    local before = left_boundary and text:sub(s - 1, s - 1) or ''
    if (s == 1 or not M.is_namespace_char(before)) and not M.is_namespace_char(text:sub(e + 1, e + 1)) then
      table.insert(ranges, { s, e })
      init = e + 1
    else
      init = s + 1
    end
  end

  return ranges
end

---@param text string
---@param needle string
---@param opts? php_namespace_refactor.FindOpts
---@return boolean
function M.contains(text, needle, opts)
  return #M.find_all(text, needle, opts) > 0
end

---Replaces every occurrence found by find_all().
---@param text string
---@param needle string
---@param replacement string
---@param opts? php_namespace_refactor.FindOpts
---@return string text
---@return integer count
function M.replace_all(text, needle, replacement, opts)
  local ranges = M.find_all(text, needle, opts)
  if #ranges == 0 then
    return text, 0
  end

  local parts = {}
  local last = 1
  for _, range in ipairs(ranges) do
    table.insert(parts, text:sub(last, range[1] - 1))
    table.insert(parts, replacement)
    last = range[2] + 1
  end
  table.insert(parts, text:sub(last))

  return table.concat(parts), #ranges
end

---Matches a declaration at the start of a single line.
---@param line string
---@return integer? start
---@return integer? finish
local function match_declaration_line(line)
  local pos = line:match('^%s*()')

  for _, modifier in ipairs(M.DECLARATION_MODIFIERS) do
    pos = line:match('^' .. modifier .. '%s+()', pos) or pos
  end

  for _, keyword in ipairs(M.NAMED_TYPE_KEYWORDS) do
    local s, after = line:match('^' .. keyword .. '%s+()[A-Za-z0-9_]+()', pos)
    if s then
      return s, after - 1
    end
  end
end

---Finds the first class, interface, trait or enum declaration, optionally
---prefixed by `abstract` and/or `final`, at the start of a line.
---@param text string
---@return string? name
---@return integer? start Byte offset of the name in `text`
---@return integer? finish
function M.class_declaration(text)
  local pos = 1
  while pos <= #text do
    local line_end = text:find('\n', pos, true) or #text + 1
    local s, e = match_declaration_line(text:sub(pos, line_end - 1))
    if s and e then
      return text:sub(pos + s - 1, pos + e - 1), pos + s - 1, pos + e - 1
    end
    pos = line_end + 1
  end
end

return M
