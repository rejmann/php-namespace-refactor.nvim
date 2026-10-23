---@mod php-namespace-refactor.app.operations.property_rename Property rename
---
---Port of PropertyRenameOperation: when a class is renamed, renames the
---constructor property typed with it (promoted or not) and its `$this->x`
---usages to follow the new class name.

local constructor_span = require('php-namespace-refactor.domain.property.constructor_span')
local declaration = require('php-namespace-refactor.domain.property.declaration')
local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')
local locator = require('php-namespace-refactor.domain.property.locator')
local path = require('php-namespace-refactor.domain.path')

local M = {}

---@class php_namespace_refactor.PropertyRenameNames
---@field old_class_name string
---@field new_class_name string
---@field expected_old_name string Conventional property name for the old class
---@field expected_new_name string Conventional property name for the new class

---Resolves the old/new property-name convention for a class rename, so a
---caller that already has a file's text (e.g. the multi-file reference
---updater, mid class rename) can fold property renaming into that same pass
---instead of reading every affected file again.
---@param old_path string
---@param new_path string
---@return php_namespace_refactor.PropertyRenameNames? nil when the class name didn't change
function M.resolve_names(old_path, new_path)
  local old_class_name = path.class_name_from_path(old_path)
  local new_class_name = path.class_name_from_path(new_path)
  if old_class_name == '' or new_class_name == '' or old_class_name == new_class_name then
    return nil
  end

  return {
    old_class_name = old_class_name,
    new_class_name = new_class_name,
    expected_old_name = locator.property_name(old_class_name),
    expected_new_name = locator.property_name(new_class_name),
  }
end

---Edits replacing every `needle` followed by a word boundary within
---[start, finish) (0-based, end-exclusive).
---@param text string
---@param start integer
---@param finish integer
---@param needle string
---@param replacement string
---@param edits php_namespace_refactor.TextEdit[]
local function replace_in_range(text, start, finish, needle, replacement, edits)
  local init = start + 1
  while true do
    local s, e = text:find(needle, init, true)
    if not s or not e or e > finish then
      return
    end
    if not text:sub(e + 1, e + 1):find('^[A-Za-z0-9_]$') then
      table.insert(edits, { start = s - 1, finish = e, text = replacement })
    end
    init = e + 1
  end
end

---Edits renaming the property of `text` typed with the renamed class.
---
---The property's declared type reads as whichever class name is present in
---the text: the new one when the class rename was already applied, or still
---the old one when called from the multi-file reference updater, whose
---class-name edits are only collected, not applied yet.
---@param text string
---@param names php_namespace_refactor.PropertyRenameNames
---@param rename_mismatched_names boolean Also rename properties not named after the old class
---@return php_namespace_refactor.TextEdit[]
function M.collect_edits(text, names, rename_mismatched_names)
  local search_class_name = text:find(names.new_class_name, 1, true) and names.new_class_name or names.old_class_name
  if not text:find(search_class_name, 1, true) then
    return {}
  end

  local match = locator.locate(text, search_class_name)
  if not match or match.property_name == names.expected_new_name then
    return {}
  end
  if match.property_name ~= names.expected_old_name and not rename_mismatched_names then
    return {}
  end

  local old_name = match.property_name
  local new_name = names.expected_new_name
  local edits = {}

  local span = constructor_span.find(text)
  if span then
    replace_in_range(text, span.constructor_start, span.body_end, '$' .. old_name, '$' .. new_name, edits)
  end
  if match.has_separate_declaration then
    local s, e = declaration.find(text, search_class_name, old_name)
    if s and e then
      replace_in_range(text, s, e, '$' .. old_name, '$' .. new_name, edits)
    end
  end
  replace_in_range(text, 0, #text, '$this->' .. old_name, '$this->' .. new_name, edits)

  return edits
end

---@class php_namespace_refactor.PropertyRenameOpts
---@field old_path string
---@field new_path string
---@field affected_files string[] Files the class rename touched; nothing else is ever considered
---@field rename_mismatched_names boolean

---Renames the property in the renamed file and in the affected files, so a
---differently-namespaced class that happens to share a short name is never
---touched.
---@param opts php_namespace_refactor.PropertyRenameOpts
---@return php_namespace_refactor.ApplyResult?
function M.execute(opts)
  local names = M.resolve_names(opts.old_path, opts.new_path)
  if not names then
    return nil
  end

  local workspace_edit = edit.new()
  local seen = {}
  for _, file in ipairs(vim.list_extend({ opts.new_path }, opts.affected_files)) do
    if not seen[file] then
      seen[file] = true
      local text = fs.read_text(file)
      if text then
        for _, text_edit in ipairs(M.collect_edits(text, names, opts.rename_mismatched_names)) do
          workspace_edit:add(file, text_edit)
        end
      end
    end
  end

  return workspace_edit:apply()
end

return M
