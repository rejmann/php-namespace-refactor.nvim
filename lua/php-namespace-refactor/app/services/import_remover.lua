---@mod php-namespace-refactor.app.services.import_remover Import remover
---
---Port of ImportRemover: once a class lands in a directory, imports between
---it and its new siblings point into the file's own namespace and are
---redundant, so they are removed (when `remove_unused_imports` is on).

local composer = require('php-namespace-refactor.infra.composer')
local config = require('php-namespace-refactor.config')
local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')
local path = require('php-namespace-refactor.domain.path')

local M = {}

---Classes declared by the files directly inside `directory`, by file name.
---@param directory string
---@return table<string, string> files Class name → path
function M.directory_classes(directory)
  local classes = {}
  for name, type in vim.fs.dir(directory) do
    local file = directory .. '/' .. name
    if type == 'file' and path.match_extension(name) then
      classes[path.class_name_from_path(file)] = file
    end
  end
  return classes
end

---Edits deleting the line-leading, non-aliased `use` statements of `text`
---that import `namespace\Name` for one of `names`.
---@param text string
---@param namespace string
---@param names table<string, any> Set of short class names
---@return php_namespace_refactor.TextEdit[]
function M.collect_edits(text, namespace, names)
  local edits = {}
  local pos = 1
  while pos <= #text do
    local line_end = text:find('\n', pos, true) or #text + 1
    local fqcn = text:sub(pos, line_end - 1):match('^use%s+\\?([A-Za-z0-9_\\]+)%s*;%s*$')
    if fqcn then
      local import_namespace, name = fqcn:match('^(.*)\\([^\\]+)$')
      if import_namespace == namespace and names[name] then
        table.insert(edits, { start = pos - 1, finish = math.min(line_end, #text), text = '' })
      end
    end
    pos = line_end + 1
  end
  return edits
end

---Removes the imports made redundant by `file` being in its directory: in
---`file`, imports of its sibling classes; in the siblings, imports of `file`.
---@param file string The moved or renamed file, at its new path
function M.execute(file)
  if not config.get().remove_unused_imports then
    return
  end

  local class_namespace = composer.class_namespace(file)
  local namespace = class_namespace.namespace
  if not namespace then
    return
  end

  local siblings = M.directory_classes(path.directory_from_path(file))
  siblings[class_namespace.class_name] = nil
  if next(siblings) == nil then
    return
  end

  local workspace_edit = edit.new()
  local function collect(target, names)
    local text = fs.read_text(target)
    for _, text_edit in ipairs(text and M.collect_edits(text, namespace, names) or {}) do
      workspace_edit:add(target, text_edit)
    end
  end

  collect(file, siblings)
  for _, sibling in pairs(siblings) do
    collect(sibling, { [class_namespace.class_name] = true })
  end

  workspace_edit:apply()
end

return M
