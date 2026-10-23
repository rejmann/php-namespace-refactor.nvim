---@mod php-namespace-refactor.app.services.moved_file_namespace_updater Moved file namespace updater
---
---Port of MovedFileNamespaceUpdater: rewrites the namespace declaration of
---a file that moved to another directory.

local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')

local M = {}

---Edit replacing the name in the first `namespace Foo\Bar;` declaration.
---Only the name changes, the surrounding lines are left as they are.
---@param text string
---@param new_namespace string
---@return php_namespace_refactor.TextEdit? nil when `text` has no namespace declaration
function M.collect_edit(text, new_namespace)
  local pos = 1
  while pos <= #text do
    local line_end = text:find('\n', pos, true) or #text + 1
    local s, e = text:sub(pos, line_end - 1):match('^%s*namespace%s+()[A-Za-z0-9_\\]+();')
    if s and e then
      return { start = pos + s - 2, finish = pos + e - 2, text = new_namespace }
    end
    pos = line_end + 1
  end
  return nil
end

---Sets the namespace declared in `file`.
---@param file string
---@param new_namespace string
---@return boolean found The file has a namespace declaration (even if it was already up to date)
function M.execute(file, new_namespace)
  local text = fs.read_text(file)
  local text_edit = text and M.collect_edit(text, new_namespace)
  if not text_edit then
    return false
  end

  local workspace_edit = edit.new()
  workspace_edit:add(file, text_edit)
  workspace_edit:apply()
  return true
end

return M
