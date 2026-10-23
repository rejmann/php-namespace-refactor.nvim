---@mod php-namespace-refactor.infra.composer Composer PSR-4 autoload
---
---Maps directories to namespaces (and back) through the `psr-4` sections of
---the nearest composer.json.

local path = require('php-namespace-refactor.domain.path')

local M = {}

M.COMPOSER_FILE = 'composer.json'

---One PSR-4 prefix → directory pair, normalized: no trailing backslash in
---the prefix, directory relative to the project root without `./` or a
---trailing slash ('' for the root itself).
---@class php_namespace_refactor.Psr4Entry
---@field prefix string
---@field directory string
---@field dev boolean From autoload-dev

---@class php_namespace_refactor.Autoload
---@field root string Project root (directory of composer.json)
---@field entries php_namespace_refactor.Psr4Entry[]

---@type table<string, { mtime: string, entries: php_namespace_refactor.Psr4Entry[] }>
local cache = {}

---Project root of `file`: the closest directory with a composer.json.
---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, M.COMPOSER_FILE)
end

---@param directory string
---@return string
local function normalize_directory(directory)
  directory = directory:gsub('\\', '/'):gsub('^%./', ''):gsub('/+$', '')
  return directory == '.' and '' or directory
end

---@param section any The `psr-4` table of autoload or autoload-dev
---@param dev boolean
---@param entries php_namespace_refactor.Psr4Entry[]
local function collect_entries(section, dev, entries)
  if type(section) ~= 'table' then
    return
  end

  for prefix, directories in pairs(section) do
    if type(directories) == 'string' then
      directories = { directories }
    end
    if type(prefix) == 'string' and type(directories) == 'table' then
      for _, directory in ipairs(directories) do
        if type(directory) == 'string' then
          table.insert(entries, {
            prefix = (prefix:gsub('\\+$', '')),
            directory = normalize_directory(directory),
            dev = dev,
          })
        end
      end
    end
  end
end

---@param composer_path string
---@return php_namespace_refactor.Psr4Entry[]
local function parse(composer_path)
  local file = io.open(composer_path, 'r')
  if not file then
    return {}
  end
  local content = file:read('*a')
  file:close()

  local ok, composer = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(composer) ~= 'table' then
    return {}
  end

  local entries = {}
  collect_entries(vim.tbl_get(composer, 'autoload', 'psr-4'), false, entries)
  collect_entries(vim.tbl_get(composer, 'autoload-dev', 'psr-4'), true, entries)
  return entries
end

---Reads the PSR-4 mappings of the project `root`, cached until composer.json
---changes (by mtime). A missing or invalid composer.json yields no entries.
---@param root string
---@return php_namespace_refactor.Autoload
function M.read(root)
  local composer_path = root .. '/' .. M.COMPOSER_FILE
  local stat = vim.uv.fs_stat(composer_path)
  if not stat then
    cache[root] = nil
    return { root = root, entries = {} }
  end

  local mtime = ('%d.%d'):format(stat.mtime.sec, stat.mtime.nsec)
  local cached = cache[root]
  if not cached or cached.mtime ~= mtime then
    cached = { mtime = mtime, entries = parse(composer_path) }
    cache[root] = cached
  end

  return { root = root, entries = cached.entries }
end

---Orders entries by a key's length, longest first, autoload before
---autoload-dev on ties. JSON objects have no key order once decoded, so
---this is what makes the most specific mapping win deterministically.
---@param entries php_namespace_refactor.Psr4Entry[]
---@param key 'prefix'|'directory'
---@return php_namespace_refactor.Psr4Entry[]
local function sorted_by(entries, key)
  local sorted = vim.list_extend({}, entries)
  table.sort(sorted, function(a, b)
    if #a[key] ~= #b[key] then
      return #a[key] > #b[key]
    end
    if a.dev ~= b.dev then
      return not a.dev
    end
    return a[key] < b[key]
  end)
  return sorted
end

---Autoload of the project `file` belongs to.
---@param file string
---@return php_namespace_refactor.Autoload?
local function autoload_of(file)
  local root = M.root(file)
  return root and M.read(root) or nil
end

---Namespace of the classes in `directory`, from the most specific PSR-4
---mapping that contains it.
---@param directory string Absolute directory
---@param autoload? php_namespace_refactor.Autoload Defaults to the one of `directory`'s project
---@return string? namespace '' for the global namespace, nil when no mapping applies
function M.namespace_from_directory(directory, autoload)
  directory = directory:gsub('/+$', '')
  -- vim.fs.root() starts at the parent of the path it gets, so pass a file
  -- inside `directory` for `directory` itself to be considered.
  autoload = autoload or autoload_of(directory .. '/_')
  if not autoload then
    return nil
  end

  local relative = ''
  if directory ~= autoload.root:gsub('/+$', '') then
    relative = path.relative_path(directory, autoload.root)
    if relative == directory then
      return nil
    end
  end

  for _, entry in ipairs(sorted_by(autoload.entries, 'directory')) do
    local rest
    if entry.directory == '' then
      rest = relative
    elseif relative == entry.directory then
      rest = ''
    elseif vim.startswith(relative, entry.directory .. '/') then
      rest = relative:sub(#entry.directory + 2)
    end

    if rest then
      local segments = vim.tbl_filter(function(segment)
        return segment ~= ''
      end, { entry.prefix, (rest:gsub('/', '\\')) })
      return table.concat(segments, '\\')
    end
  end

  return nil
end

---Absolute directory where the classes of `namespace` live, from the
---longest PSR-4 prefix that contains it.
---@param namespace string
---@param autoload php_namespace_refactor.Autoload
---@return string? directory nil when no mapping applies
function M.directory_from_namespace(namespace, autoload)
  namespace = namespace:gsub('^\\+', ''):gsub('\\+$', '')

  for _, entry in ipairs(sorted_by(autoload.entries, 'prefix')) do
    local rest
    if entry.prefix == '' then
      rest = namespace
    elseif namespace == entry.prefix then
      rest = ''
    elseif vim.startswith(namespace, entry.prefix .. '\\') then
      rest = namespace:sub(#entry.prefix + 2)
    end

    if rest then
      local segments = vim.tbl_filter(function(segment)
        return segment ~= ''
      end, { autoload.root, entry.directory, (rest:gsub('\\', '/')) })
      return table.concat(segments, '/')
    end
  end

  return nil
end

---@class php_namespace_refactor.ClassNamespace
---@field namespace? string Namespace of the file, nil for the global namespace
---@field class_name string
---@field full_namespace string Fully qualified class name

---Fully qualified name of the class declared by `file`, from its location.
---@param file string Absolute path
---@param autoload? php_namespace_refactor.Autoload Defaults to the one of `file`'s project
---@return php_namespace_refactor.ClassNamespace
function M.class_namespace(file, autoload)
  autoload = autoload or autoload_of(file)
  local class_name = path.class_name_from_path(file)
  local namespace = autoload and M.namespace_from_directory(path.directory_from_path(file), autoload) or nil
  if namespace == '' then
    namespace = nil
  end

  return {
    namespace = namespace,
    class_name = class_name,
    full_namespace = namespace and (namespace .. '\\' .. class_name) or class_name,
  }
end

---Drops cached composer.json contents. Meant for tests.
function M._reset()
  cache = {}
end

return M
