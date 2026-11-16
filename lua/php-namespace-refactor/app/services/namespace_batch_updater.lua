---@mod php-namespace-refactor.app.services.namespace_batch_updater Namespace batch updater
---
---Port of NamespaceBatchUpdater: everything that follows one PHP file being
---moved or renamed - its class name, its namespace declaration and the
---references in the rest of the project.

local class_name_updater = require('php-namespace-refactor.app.services.class_name_updater')
local composer = require('php-namespace-refactor.infra.composer')
local fs = require('php-namespace-refactor.infra.fs')
local moved_file_namespace_updater = require('php-namespace-refactor.app.services.moved_file_namespace_updater')
local multi_file_reference_updater = require('php-namespace-refactor.app.services.multi_file_reference_updater')
local path = require('php-namespace-refactor.domain.path')
local patterns = require('php-namespace-refactor.domain.php.patterns')

local M = {}

---Name declared by `file` (its `namespace` and class declarations), for a
---file that didn't move but whose declarations no longer match its path.
---@param file string
---@return php_namespace_refactor.ClassNamespace?
local function declared(file)
  local text = fs.read_text(file)
  local class_name = text and patterns.class_declaration(text)
  if not class_name then
    return nil
  end
  local namespace = ('\n' .. text):match('\n%s*namespace%s+([A-Za-z0-9_\\]+)%s*;')
  return {
    namespace = namespace,
    class_name = class_name,
    full_namespace = namespace and (namespace .. '\\' .. class_name) or class_name,
  }
end

---@param old_path string Where the file was (the same as `new_path` to bring
---  the declarations of a file that didn't move in line with its path)
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

  local old
  if old_path == new_path then
    old = declared(new_path)
    if not old or old.full_namespace == new.full_namespace then
      return {}
    end
    -- The reference update takes the old class name from the old path.
    local directory = path.directory_from_path(new_path)
    old_path = ('%s/%s%s'):format(directory, old.class_name, path.extension_from_path(new_path))
  else
    old = composer.class_namespace(old_path, autoload)
  end

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
