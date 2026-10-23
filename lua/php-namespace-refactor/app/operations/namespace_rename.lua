---@mod php-namespace-refactor.app.operations.namespace_rename Namespace rename
---
---Port of NamespaceRenameOperation: changing the namespace of a class moves
---its file to the directory PSR-4 maps that namespace to.

local composer = require('php-namespace-refactor.infra.composer')
local move = require('php-namespace-refactor.app.move')
local path = require('php-namespace-refactor.domain.path')

local M = {}

---New path of `file` for the namespace `new_namespace`.
---@param file string
---@param new_namespace string
---@return string? target
---@return string? err
function M.target(file, new_namespace)
  local root = composer.root(file)
  local directory = root and composer.directory_from_namespace(new_namespace, composer.read(root))
  if not directory then
    return nil, ('no psr-4 mapping found for namespace %s'):format(new_namespace)
  end
  return ('%s/%s%s'):format(directory, path.class_name_from_path(file), path.extension_from_path(file))
end

---@param file string
---@param new_namespace string
---@param opts? php_namespace_refactor.MoveOpts
---@return boolean ok
---@return string? err
function M.execute(file, new_namespace, opts)
  local target, err = M.target(file, new_namespace)
  if not target then
    return false, err
  end
  return move.move(file, target, opts)
end

return M
