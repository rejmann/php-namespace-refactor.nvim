---@mod php-namespace-refactor.app.services.multi_file_reference_updater Multi-file reference updater
---
---Port of MultiFileReferenceUpdater: after a class moved or was renamed,
---updates every file referencing it - fully qualified names, the short class
---name, `use` statements for files left behind in the old directory and,
---when enabled, the constructor property typed with it - in one edit.

local composer = require('php-namespace-refactor.infra.composer')
local config = require('php-namespace-refactor.config')
local edit = require('php-namespace-refactor.infra.edit')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local path = require('php-namespace-refactor.domain.path')
local patterns = require('php-namespace-refactor.domain.php.patterns')
local property_rename = require('php-namespace-refactor.app.operations.property_rename')
local use_statement = require('php-namespace-refactor.domain.php.use_statement')

local M = {}

---@class php_namespace_refactor.ReferenceUpdateOpts
---@field old_namespace string Fully qualified name of the class before the change
---@field new_namespace string Fully qualified name after it
---@field old_path string
---@field new_path string
---@field root? string Project root (default: the composer root of new_path)
---@field index? php_namespace_refactor.Index (default: the project's index)

---Files whose text on disk contains `needle`, besides `ignore_file`.
---@param list string[]
---@param needle string
---@param ignore_file string
---@return string[]
local function scan(list, needle, ignore_file)
  local result = {}
  for _, file in ipairs(list) do
    if file ~= ignore_file then
      local text = fs.read_file(file)
      if text and text:find(needle, 1, true) then
        table.insert(result, file)
      end
    end
  end
  return result
end

---Adds one replacement per range to `workspace_edit`, skipping ranges that
---fall inside one of `exclude_within` (e.g. the short class name inside its
---own FQCN, already being replaced, which would overlap).
---@param workspace_edit php_namespace_refactor.WorkspaceEdit
---@param file string
---@param ranges [integer, integer][] 1-based inclusive, from patterns.find_all()
---@param replacement string
---@param exclude_within? [integer, integer][]
local function add_replacements(workspace_edit, file, ranges, replacement, exclude_within)
  for _, range in ipairs(ranges) do
    local excluded = vim.iter(exclude_within or {}):any(function(outer)
      return range[1] >= outer[1] and range[2] <= outer[2]
    end)
    if not excluded then
      workspace_edit:replace(file, range[1] - 1, range[2], replacement)
    end
  end
end

---Updates the references to a moved or renamed class.
---@param opts php_namespace_refactor.ReferenceUpdateOpts
---@return string[] affected Files that were considered (referencing the class or in its old directory)
function M.execute(opts)
  local root = opts.root or composer.root(opts.new_path)
  if not root then
    return {}
  end
  local index = opts.index or require('php-namespace-refactor.infra.index').get(root)

  local old_directory = path.directory_from_path(opts.old_path)
  local moved = path.directory_from_path(opts.new_path) ~= old_directory
  local class_name = path.class_name_from_path(opts.old_path)
  local new_class_name = path.class_name_from_path(opts.new_path)
  local renamed = class_name ~= new_class_name
  local import = use_statement.statement(opts.new_namespace)
  local ignore_file = opts.new_path

  -- Resolved once so property renaming is folded into the same per-file pass
  -- (and edit) as the class name replacement.
  local property_settings = config.property_rename_settings()
  local property_names = property_settings.enabled and property_rename.resolve_names(opts.old_path, opts.new_path)
    or nil

  local workspace_edit = edit.new()

  ---@param file string
  ---@param text string
  local function add_property_edits(file, text)
    if property_names then
      for _, text_edit in
        ipairs(property_rename.collect_edits(text, property_names, property_settings.rename_mismatched_names))
      do
        workspace_edit:add(file, text_edit)
      end
    end
  end

  ---A file left in the old directory referenced the class without importing
  ---it (same namespace); now that the class moved away it needs a `use`.
  ---@param file string
  ---@param text string
  local function add_use_statement(file, text)
    if not moved or path.directory_from_path(file) ~= old_directory or not patterns.contains(text, class_name) then
      return
    end
    local location = use_statement.locate(text)
    if location.index == 0 then
      return
    end
    local text_edit = use_statement.inject(text, location, import)
    if text_edit then
      workspace_edit:add(file, text_edit)
    end
  end

  local all_files = files.list(root)
  local affected = {}
  local affected_set = {}
  for _, list in ipairs({ index:files_using(opts.old_namespace), scan(all_files, opts.old_namespace, ignore_file) }) do
    for _, file in ipairs(list) do
      if file ~= ignore_file and not affected_set[file] then
        affected_set[file] = true
        table.insert(affected, file)
      end
    end
  end

  for _, file in ipairs(affected) do
    local text = fs.read_text(file)
    if text then
      local namespace_ranges = patterns.find_all(text, opts.old_namespace, { left_boundary = false })
      add_replacements(workspace_edit, file, namespace_ranges, opts.new_namespace)
      if renamed then
        add_replacements(workspace_edit, file, patterns.find_all(text, class_name), new_class_name, namespace_ranges)
      end
      add_property_edits(file, text)

      -- The replacement above already turns this file's own `use` line into
      -- the new one; appending another would duplicate it.
      if #namespace_ranges == 0 then
        add_use_statement(file, text)
      end
    end
  end

  -- Files in the old directory, which may reference the class by its short name.
  local same_directory = {}
  for _, file in ipairs(all_files) do
    if file ~= ignore_file and not affected_set[file] and path.directory_from_path(file) == old_directory then
      table.insert(same_directory, file)
      local text = fs.read_text(file)
      if text then
        if renamed then
          add_replacements(workspace_edit, file, patterns.find_all(text, class_name), new_class_name)
        end
        add_use_statement(file, text)
        add_property_edits(file, text)
      end
    end
  end

  -- The renamed class's own file covers a self-typed property (e.g. a
  -- linked-list node), never part of the lists above.
  local own_text = property_names and fs.read_text(opts.new_path)
  if own_text then
    add_property_edits(opts.new_path, own_text)
  end

  local result = workspace_edit:apply()
  for file, err in pairs(result.errors) do
    vim.notify(('php-namespace-refactor: could not update %s: %s'):format(file, err), vim.log.levels.WARN)
  end

  return vim.list_extend(affected, same_directory)
end

return M
