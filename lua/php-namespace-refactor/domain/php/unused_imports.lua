---@mod php-namespace-refactor.domain.php.unused_imports Missing imports
---
---Port of UnusedImportDetector: which classes a file references without
---importing them.

local patterns = require('php-namespace-refactor.domain.php.patterns')

local M = {}

---Short names (last segment) of every `use` statement in `text`.
---@param text string
---@return table<string, true>
local function imported_short_names(text)
  local imported = {}
  local init = 1
  while true do
    local s, e, namespace = text:find('use%s+([A-Za-z0-9_\\]+)', init)
    if not s then
      break
    end
    -- Skip words ending in "use" (e.g. "because Foo").
    if s == 1 or not patterns.is_namespace_char(text:sub(s - 1, s - 1)) then
      imported[namespace:match('([^\\]*)$')] = true
    end
    init = e + 1
  end
  return imported
end

---Classes among `classes` that `text` references (as a whole identifier) but
---doesn't import yet, in the order given and without duplicates.
---@param text string
---@param classes string[] Short class names
---@return string[]
function M.detect(text, classes)
  local imported = imported_short_names(text)
  local result = {}
  local seen = {}

  for _, class_name in ipairs(classes) do
    if not seen[class_name] and not imported[class_name] and patterns.contains(text, class_name) then
      table.insert(result, class_name)
    end
    seen[class_name] = true
  end

  return result
end

return M
