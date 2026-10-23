---@mod php-namespace-refactor.app.operations.class_rename Class rename
---
---Port of ClassRenameOperation: renaming a class renames its file, and the
---move does the rest.

local move = require('php-namespace-refactor.app.move')
local path = require('php-namespace-refactor.domain.path')

local M = {}

---New path of `file` for a class named `new_class_name`, keeping the full
---configured extension (e.g. `.class.php`).
---@param file string
---@param new_class_name string
---@return string
function M.target(file, new_class_name)
  return ('%s/%s%s'):format(path.directory_from_path(file), new_class_name, path.extension_from_path(file))
end

---@param file string
---@param new_class_name string
---@param opts? php_namespace_refactor.MoveOpts
---@return boolean ok
---@return string? err
function M.execute(file, new_class_name, opts)
  return move.move(file, M.target(file, new_class_name), opts)
end

return M
