---@mod php-namespace-refactor.app.services.namespace_batch_updater Namespace batch updater
---
---Port of NamespaceBatchUpdater: everything that follows one PHP file being
---moved or renamed - its class name, its namespace declaration and the
---references in the rest of the project.

local class_name_updater = require('php-namespace-refactor.app.services.class_name_updater')
local composer = require('php-namespace-refactor.infra.composer')
local moved_file_namespace_updater = require('php-namespace-refactor.app.services.moved_file_namespace_updater')
local multi_file_reference_updater = require('php-namespace-refactor.app.services.multi_file_reference_updater')

local M = {}

---@param old_path string Where the file was
---@param new_path string Where it is now (already moved on disk)
---@return string[] affected Files the reference update considered
function M.execute(old_path, new_path)
  local root = composer.root(new_path)
  if not root then
    return {}
  end
  local autoload = composer.read(root)

  local new = composer.class_namespace(new_path, autoload)
  if not new.namespace then
    return {}
  end
  local old = composer.class_namespace(old_path, autoload)

  if new.class_name ~= old.class_name then
    class_name_updater.execute(new_path)
  end

  if not moved_file_namespace_updater.execute(new_path, new.namespace) then
    return {}
  end

  return multi_file_reference_updater.execute({
    old_namespace = old.full_namespace,
    new_namespace = new.full_namespace,
    old_path = old_path,
    new_path = new_path,
    root = root,
  })
end

return M
