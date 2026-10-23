---@mod php-namespace-refactor.domain.rename Rename detection
---
---Port of RenameTypeDetector, ExtractNameFromCursor and RenameValidator:
---what the line under the cursor declares, and whether a new name is valid.

local patterns = require('php-namespace-refactor.domain.php.patterns')

local M = {}

---@alias php_namespace_refactor.RenameType 'namespace'|'class'

---@param line string
---@return string?
local function namespace_name(line)
  return line:match('^%s*namespace%s+([A-Za-z0-9_\\]+)%s*;')
end

---What the line declares: a namespace or a class (also interface, trait
---and enum).
---@param line string
---@return php_namespace_refactor.RenameType?
function M.detect_type(line)
  if line:match('^%s*namespace%s') then
    return 'namespace'
  end
  if patterns.class_declaration(line) then
    return 'class'
  end
  return nil
end

---Name declared by the line: the namespace or the class name.
---@param line string
---@return string?
function M.extract_name(line)
  return namespace_name(line) or (patterns.class_declaration(line))
end

---@param value string
---@return string?
local function validate_class_name(value)
  if value:match('^%d') then
    return 'Class name cannot start with a number'
  end
  if value:find('-', 1, true) then
    return 'Class name cannot contain hyphens (-)'
  end
  if value:match('%s') then
    return 'Class name cannot contain spaces'
  end
  if not value:match('^[A-Za-z_][A-Za-z0-9_]*$') then
    return 'Class name must start with a letter or underscore and contain only letters, digits and underscores'
  end
  return nil
end

---@param value string
---@return string?
local function validate_namespace(value)
  if vim.startswith(value, '\\') then
    return 'Cannot start with \\'
  end
  if vim.endswith(value, '\\') then
    return 'Cannot end with \\'
  end
  if value:find('\\\\', 1, true) then
    return 'Cannot contain double \\\\'
  end
  if not value:match('^[A-Za-z]') then
    return 'Must start with a letter'
  end
  for segment in vim.gsplit(value, '\\', { plain = true }) do
    if not segment:match('^[A-Za-z_][A-Za-z0-9_]*$') then
      return 'Invalid format. Use: Foo\\Bar'
    end
  end
  return nil
end

---Checks a new name for a class or a namespace.
---@param value string
---@param type php_namespace_refactor.RenameType
---@return string? err nil when the name is valid
function M.validate(value, type)
  if vim.trim(value) == '' then
    return 'Name cannot be empty'
  end
  if type == 'class' then
    return validate_class_name(value)
  end
  return validate_namespace(value)
end

return M
