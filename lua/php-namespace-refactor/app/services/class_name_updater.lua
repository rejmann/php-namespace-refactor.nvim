---@mod php-namespace-refactor.app.services.class_name_updater Class name updater
---
---Port of ClassNameUpdater: after a file is renamed, renames the class it
---declares (and its references inside the file) to match the file name.

local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')
local path = require('php-namespace-refactor.domain.path')
local patterns = require('php-namespace-refactor.domain.php.patterns')

local M = {}

---Edits renaming the declared class of `text` to the class name of `file`.
---@param text string
---@param file string
---@return php_namespace_refactor.TextEdit[]
function M.collect_edits(text, file)
  local current_name = patterns.class_declaration(text)
  local expected_name = path.class_name_from_path(file)
  if not current_name or current_name == expected_name then
    return {}
  end

  return vim.tbl_map(function(range)
    return { start = range[1] - 1, finish = range[2], text = expected_name }
  end, patterns.find_all(text, current_name))
end

---Renames the class declared in `file` to its file name, if they differ.
---@param file string
---@return boolean updated
function M.execute(file)
  local text = fs.read_text(file)
  if not text then
    return false
  end

  local edits = M.collect_edits(text, file)
  if #edits == 0 then
    return false
  end

  local workspace_edit = edit.new()
  for _, text_edit in ipairs(edits) do
    workspace_edit:add(file, text_edit)
  end
  return #workspace_edit:apply().changed > 0
end

return M
