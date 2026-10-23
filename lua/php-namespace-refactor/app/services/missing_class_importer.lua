---@mod php-namespace-refactor.app.services.missing_class_importer Missing class importer
---
---Port of MissingClassImporter: a class that used its old siblings by short
---name (same namespace, no import) needs `use` statements for them once it
---moves to another directory.

local composer = require('php-namespace-refactor.infra.composer')
local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')
local import_remover = require('php-namespace-refactor.app.services.import_remover')
local path = require('php-namespace-refactor.domain.path')
local unused_imports = require('php-namespace-refactor.domain.php.unused_imports')
local use_statement = require('php-namespace-refactor.domain.php.use_statement')

local M = {}

---Edit importing the classes of `old_directory` that `text` uses.
---@param text string Contents of the moved file
---@param old_directory string
---@param own_class_name string Class of the moved file, never imported
---@return php_namespace_refactor.TextEdit?
function M.collect_edit(text, old_directory, own_class_name)
  local classes = vim.tbl_keys(import_remover.directory_classes(old_directory))
  table.sort(classes)
  classes = vim.tbl_filter(function(class_name)
    return class_name ~= own_class_name
  end, classes)

  local used = unused_imports.detect(text, classes)
  if #used == 0 then
    return nil
  end

  local full_namespaces = vim.tbl_map(function(class_name)
    return composer.class_namespace(old_directory .. '/' .. class_name .. '.php').full_namespace
  end, used)

  local location = use_statement.locate(text)
  if location.index == 0 then
    return nil
  end
  return use_statement.inject(text, location, use_statement.statements(full_namespaces))
end

---@param old_path string
---@param new_path string
---@return boolean imported
function M.execute(old_path, new_path)
  local old_directory = path.directory_from_path(old_path)
  if old_directory == path.directory_from_path(new_path) then
    return false
  end

  local text = fs.read_text(new_path)
  local text_edit = text and M.collect_edit(text, old_directory, path.class_name_from_path(new_path))
  if not text_edit then
    return false
  end

  local workspace_edit = edit.new()
  workspace_edit:add(new_path, text_edit)
  return #workspace_edit:apply().changed > 0
end

return M
