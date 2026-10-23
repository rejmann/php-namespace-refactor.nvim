---@mod php-namespace-refactor.config Configuration

local M = {}

---Child flags of `rename_properties` when given as a table. Each one
---defaults to `true` whenever the feature is enabled.
---@class php_namespace_refactor.RenamePropertiesOpts
---@field rename_mismatched_names? boolean Also rename properties whose name doesn't match the class name

---@class php_namespace_refactor.Config
---@field ignored_directories string[] Path fragments skipped while scanning the workspace
---@field auto_import_namespace boolean Add `use` statements for classes that lose their implicit same-namespace import
---@field remove_unused_imports boolean Remove `use` statements left unused by a move
---@field additional_extensions string[] File extensions handled besides `php`
---@field rename boolean Enable the rename command
---@field edit_files_in_background boolean Edit files on disk instead of opening a buffer for each one
---@field rename_properties boolean|php_namespace_refactor.RenamePropertiesOpts Rename typed properties along with their class

---@class php_namespace_refactor.Opts
---@field ignored_directories? string[]
---@field auto_import_namespace? boolean
---@field remove_unused_imports? boolean
---@field additional_extensions? string[]
---@field rename? boolean
---@field edit_files_in_background? boolean
---@field rename_properties? boolean|php_namespace_refactor.RenamePropertiesOpts

---@type php_namespace_refactor.Config
M.defaults = {
  ignored_directories = { '/vendor/', '/var/', '/cache/' },
  auto_import_namespace = true,
  remove_unused_imports = true,
  additional_extensions = { 'php' },
  rename = true,
  edit_files_in_background = true,
  rename_properties = false,
}

---Options given to setup(), merged over `vim.g.php_namespace_refactor`.
---@type php_namespace_refactor.Opts
local setup_opts = {}

---@param name string
---@param value any
---@param validator vim.validate.Validator
---@param optional? boolean
local function validate(name, value, validator, optional)
  if vim.fn.has('nvim-0.11') == 1 then
    vim.validate(name, value, validator, optional)
  elseif type(validator) == 'function' then
    -- The 0.10 table form reads a function validator's third item as its
    -- error message, so optional has to be handled here.
    if not (optional and value == nil) then
      vim.validate({ [name] = { value, validator, 'valid value' } })
    end
  else
    vim.validate({ [name] = { value, validator, optional } })
  end
end

---@param value any
---@return boolean
local function is_string_list(value)
  return vim.islist(value) and vim.iter(value):all(function(item)
    return type(item) == 'string'
  end)
end

---Checks every option of a (partial) config.
---@param config table
---@return boolean ok
---@return string? err
function M.validate(config)
  local ok, err = pcall(function()
    validate('ignored_directories', config.ignored_directories, is_string_list, true)
    validate('additional_extensions', config.additional_extensions, is_string_list, true)
    validate('auto_import_namespace', config.auto_import_namespace, 'boolean', true)
    validate('remove_unused_imports', config.remove_unused_imports, 'boolean', true)
    validate('rename', config.rename, 'boolean', true)
    validate('edit_files_in_background', config.edit_files_in_background, 'boolean', true)
    validate('rename_properties', config.rename_properties, { 'boolean', 'table' }, true)

    local rename_properties = config.rename_properties
    if type(rename_properties) == 'table' then
      for key, value in pairs(rename_properties) do
        if key ~= 'rename_mismatched_names' then
          error(('rename_properties: unknown key "%s"'):format(tostring(key)), 0)
        end
        validate('rename_properties.' .. key, value, 'boolean')
      end
    end
  end)
  if ok then
    return true
  end
  -- Drop the "file:line: " position vim.validate() adds, it means nothing to users.
  return false, (tostring(err):gsub('^[^:]*:%d+: ', ''))
end

---Stores options on top of `vim.g.php_namespace_refactor`. Calling it is
---optional: the plugin works with the defaults or with `vim.g` alone.
---@param opts? php_namespace_refactor.Opts
function M.setup(opts)
  opts = opts or {}
  local ok, err = M.validate(opts)
  if not ok then
    error('php-namespace-refactor: invalid config: ' .. tostring(err), 2)
  end
  setup_opts = vim.tbl_extend('force', setup_opts, opts)
end

---Options set by the user (`vim.g.php_namespace_refactor`, then setup()),
---without the defaults and unvalidated.
---@return table
function M.user_opts()
  local global_opts = vim.g.php_namespace_refactor
  return vim.tbl_extend('force', type(global_opts) == 'table' and global_opts or {}, setup_opts)
end

---Keys of `opts` that aren't options of this plugin, sorted.
---@param opts table
---@return string[]
function M.unknown_keys(opts)
  local unknown = vim.tbl_filter(function(key)
    return M.defaults[key] == nil
  end, vim.tbl_keys(opts))
  table.sort(unknown)
  return unknown
end

---Resolves the effective config: defaults, then `vim.g.php_namespace_refactor`,
---then setup() options. Merging is shallow on purpose, so a list option
---replaces the default list instead of being merged index by index. An
---invalid config is reported and the defaults are used instead.
---@return php_namespace_refactor.Config
function M.get()
  local global_opts = vim.g.php_namespace_refactor or {}
  local merged = vim.tbl_extend('force', vim.deepcopy(M.defaults), global_opts, setup_opts)

  local ok, err = M.validate(merged)
  if not ok then
    vim.notify('php-namespace-refactor: invalid config: ' .. tostring(err), vim.log.levels.ERROR)
    return vim.deepcopy(M.defaults)
  end

  return merged
end

---@alias php_namespace_refactor.PolymorphicFlag { enabled: boolean, [string]: boolean }

---Resolves an option that accepts either a boolean or a table of child flags
---(e.g. `rename_properties`).
---
---A bare `true` (or any table, even `{}`) enables the feature and defaults
---every child flag to `true` as well; a bare `false` (or `nil`) disables
---everything. The table form only exists to dial a specific child back to
---`false` - there's no way to enable a child while leaving the parent disabled.
---@param value boolean|table<string, boolean>|nil
---@param child_keys string[]
---@return php_namespace_refactor.PolymorphicFlag
function M.get_polymorphic_flag(value, child_keys)
  local enabled = type(value) == 'table' or value == true

  local flag = { enabled = enabled }
  for _, key in ipairs(child_keys) do
    if type(value) == 'table' then
      flag[key] = value[key] ~= false
    else
      flag[key] = enabled
    end
  end

  return flag
end

---@class php_namespace_refactor.PropertyRenameSettings
---@field enabled boolean
---@field rename_mismatched_names boolean

---Resolves `rename_properties` into its enabled flag and child flags.
---@param config? php_namespace_refactor.Config Defaults to M.get()
---@return php_namespace_refactor.PropertyRenameSettings
function M.property_rename_settings(config)
  config = config or M.get()
  local flag = M.get_polymorphic_flag(config.rename_properties, { 'rename_mismatched_names' })

  return {
    enabled = flag.enabled,
    rename_mismatched_names = flag.rename_mismatched_names,
  }
end

---Clears setup() options. Meant for tests.
function M._reset()
  setup_opts = {}
end

return M
