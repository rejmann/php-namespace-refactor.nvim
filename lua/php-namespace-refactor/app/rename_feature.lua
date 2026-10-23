---@mod php-namespace-refactor.app.rename_feature Rename
---
---Port of RenameFeature and RenameHandler: with the cursor on a `namespace`
---or class declaration, asks for a new name and renames the class (its
---file) or moves it to the new namespace's directory.

local class_rename = require('php-namespace-refactor.app.operations.class_rename')
local config = require('php-namespace-refactor.config')
local namespace_rename = require('php-namespace-refactor.app.operations.namespace_rename')
local path = require('php-namespace-refactor.domain.path')
local rename = require('php-namespace-refactor.domain.rename')

local M = {}

---@param msg string
---@param level? integer
local function notify(msg, level)
  vim.notify('PhpNamespaceRefactor: ' .. msg, level or vim.log.levels.INFO)
end

---Asks for a valid name, asking again (with the error shown) until the
---input is valid or cancelled.
---@param default string
---@param type php_namespace_refactor.RenameType
---@param on_confirm fun(name: string)
local function ask(default, type, on_confirm)
  local prompt = type == 'namespace' and 'New namespace: ' or 'New class name: '
  vim.ui.input({ prompt = prompt, default = default }, function(input)
    if input == nil then
      return
    end
    local err = rename.validate(input, type)
    if err then
      notify(err, vim.log.levels.ERROR)
      ask(input, type, on_confirm)
      return
    end
    on_confirm(input)
  end)
end

---Renames the class or namespace declared on the cursor line of the current
---buffer.
---@param opts? php_namespace_refactor.MoveOpts
function M.rename(opts)
  if not config.get().rename then
    notify('rename is disabled (rename = false)', vim.log.levels.WARN)
    return
  end

  local file = vim.api.nvim_buf_get_name(0)
  if file == '' or not path.match_extension(file) then
    notify('not a PHP file', vim.log.levels.WARN)
    return
  end

  local line = vim.api.nvim_get_current_line()
  local type = rename.detect_type(line)
  local current = rename.extract_name(line)
  if not type or not current then
    notify('place the cursor on the namespace or class declaration', vim.log.levels.WARN)
    return
  end

  ask(current, type, function(name)
    if name == current then
      return
    end

    local ok, err
    if type == 'namespace' then
      ok, err = namespace_rename.execute(file, name, opts)
    else
      ok, err = class_rename.execute(file, name, opts)
    end
    if not ok then
      notify(tostring(err), vim.log.levels.ERROR)
    end
  end)
end

return M
