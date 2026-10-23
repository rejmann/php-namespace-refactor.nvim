---@mod php-namespace-refactor.domain.property.locator Typed property locator
---
---Port of ClassTypedPropertyLocator and PropertyNameResolver.

local constructor_span = require('php-namespace-refactor.domain.property.constructor_span')
local declaration = require('php-namespace-refactor.domain.property.declaration')

local M = {}

---@class php_namespace_refactor.PropertyMatch
---@field property_name string
---@field is_promoted boolean Declared by constructor promotion
---@field has_separate_declaration boolean Declared in the class body as well

---Conventional property name for a class: `UserRepository` → `userRepository`.
---@param class_name string
---@return string
function M.property_name(class_name)
  return class_name:sub(1, 1):lower() .. class_name:sub(2)
end

---@param char string
---@return boolean
local function is_word_char(char)
  return char:find('^[A-Za-z0-9_]$') ~= nil
end

---Occurrences of `word` delimited by word boundaries (like JS `\bword\b`).
---@param text string
---@param word string
---@return fun(): integer?, integer? iterator of 1-based inclusive ranges
local function words(text, word)
  local init = 1
  return function()
    while true do
      local s, e = text:find(word, init, true)
      if not s or not e then
        return nil
      end
      init = s + 1
      if not is_word_char(text:sub(s - 1, s - 1)) and not is_word_char(text:sub(e + 1, e + 1)) then
        return s, e
      end
    end
  end
end

---Splits a parameter list on top-level commas.
---@param params string
---@return string[]
local function split_params(params)
  local result = {}
  local depth = 0
  local current = {}

  for char in params:gmatch('.') do
    if char == '(' or char == '[' or char == '{' then
      depth = depth + 1
    elseif char == ')' or char == ']' or char == '}' then
      depth = depth - 1
    end

    if char == ',' and depth == 0 then
      table.insert(result, table.concat(current))
      current = {}
    else
      table.insert(current, char)
    end
  end

  local last = table.concat(current)
  if vim.trim(last) ~= '' then
    table.insert(result, last)
  end
  return result
end

---@param param string
---@return string
local function strip_attributes(param)
  return vim.trim((param:gsub('#%[[^%]]*%]', ' ')))
end

---@param param string
---@return boolean
local function has_modifier(param)
  for _, keyword in ipairs({ 'public', 'protected', 'private', 'readonly' }) do
    if words(param, keyword)() then
      return true
    end
  end
  return false
end

---Whether `prefix` ends with promotion modifiers: a visibility, optionally
---followed or preceded by `readonly`.
---@param prefix string
---@return boolean
local function ends_with_promotion(prefix)
  for _, visibility in ipairs(declaration.VISIBILITIES) do
    if
      prefix:match('%f[A-Za-z0-9_]' .. visibility .. '%s+$')
      or prefix:match('%f[A-Za-z0-9_]' .. visibility .. '%s+readonly%s+$')
      or prefix:match('%f[A-Za-z0-9_]readonly%s+' .. visibility .. '%s+$')
    then
      return true
    end
  end
  return false
end

---Name of the `$variable` typed `class_name` in `param`, optionally only
---when promotion modifiers precede the type.
---@param param string
---@param class_name string
---@param promoted boolean
---@return string?
local function match_typed_variable(param, class_name, promoted)
  for s, e in words(param, class_name) do
    local name = param:match('^%s+%$([A-Za-z0-9_]+)', e + 1)
    if name then
      local prefix = param:sub(1, s - 1):gsub('%?$', '')
      if not promoted or ends_with_promotion(prefix) then
        return name
      end
    end
  end
  return nil
end

---@param body string
---@param var_name string
---@return boolean
local function is_assigned_to_this(body, var_name)
  local name = vim.pesc(var_name)
  return body:find('%$this%->' .. name .. '%s*=%s*%$' .. name .. '%s*;') ~= nil
end

---@param param string
---@param body string
---@param text string
---@param class_name string
---@return php_namespace_refactor.PropertyMatch?
local function match_param(param, body, text, class_name)
  local cleaned = strip_attributes(param)

  local promoted_name = match_typed_variable(cleaned, class_name, true)
  if promoted_name then
    return { property_name = promoted_name, is_promoted = true, has_separate_declaration = false }
  end

  if has_modifier(cleaned) then
    return nil
  end
  local plain_name = match_typed_variable(cleaned, class_name, false)
  if not plain_name or not is_assigned_to_this(body, plain_name) then
    return nil
  end

  return {
    property_name = plain_name,
    is_promoted = false,
    has_separate_declaration = declaration.find(text, class_name, plain_name) ~= nil,
  }
end

---Locates the single constructor property that represents an instance of
---`class_name` - promoted or not, readonly or not. Returns nil when there's
---no such property, or when more than one parameter shares that type
---(renaming either would be a guess that risks a variable-name collision).
---@param text string
---@param class_name string
---@return php_namespace_refactor.PropertyMatch?
function M.locate(text, class_name)
  local span = constructor_span.find(text)
  if not span then
    return nil
  end

  local params = text:sub(span.params_start + 1, span.params_end)
  local body = text:sub(span.body_start + 1, span.body_end)

  local candidates = {}
  for _, param in ipairs(split_params(params)) do
    local match = match_param(param, body, text, class_name)
    if match then
      table.insert(candidates, match)
    end
  end

  return #candidates == 1 and candidates[1] or nil
end

return M
