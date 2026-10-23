---@mod php-namespace-refactor.infra.index Namespace index
---
---Which files import which classes, per project, so a move only has to read
---the files that actually reference the moved class. Persisted under
---stdpath('cache') and rebuilt incrementally: only files whose mtime changed
---since the last build are parsed again.

local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')

local M = {}

M.VERSION = 1

---Files parsed per event loop iteration while building.
M.CHUNK_SIZE = 200

---@class php_namespace_refactor.IndexEntry
---@field declares? string Namespace declared by the file
---@field imports string[] Fully qualified names imported with `use`
---@field mtime? string mtime of the file when it was parsed

---Parses the namespace declaration and the `use` imports of a file.
---@param content string
---@return php_namespace_refactor.IndexEntry
function M.parse(content)
  local entry = { imports = {} }
  local seen = {}

  for line in vim.gsplit(content, '\n', { plain = true }) do
    if not entry.declares then
      entry.declares = line:match('^%s*namespace%s+\\?([A-Za-z0-9_\\]+)%s*;')
    end

    local import = line:match('^use%s+\\?([A-Za-z0-9_\\]+)%s*;')
      or line:match('^use%s+\\?([A-Za-z0-9_\\]+)%s+as%s+[A-Za-z0-9_]+%s*;')
    if import and not seen[import] then
      seen[import] = true
      table.insert(entry.imports, import)
    end
  end

  return entry
end

---@param file string
---@return string?
local function mtime_of(file)
  local stat = vim.uv.fs_stat(file)
  return stat and ('%d.%d'):format(stat.mtime.sec, stat.mtime.nsec) or nil
end

---@class php_namespace_refactor.Index
---@field root string
---@field path string JSON file the index is saved to
---@field ready boolean A build has completed
---@field private entries table<string, php_namespace_refactor.IndexEntry>
---@field private usages table<string, table<string, true>>
---@field private building boolean
---@field private callbacks fun()[]
local Index = {}
Index.__index = Index

---@param root string
---@param path string
---@return php_namespace_refactor.Index
function M.new(root, path)
  return setmetatable({
    root = root,
    path = path,
    ready = false,
    entries = {},
    usages = {},
    building = false,
    callbacks = {},
  }, Index)
end

---Files importing `namespace`, sorted.
---@param namespace string
---@return string[]
function Index:files_using(namespace)
  local result = vim.tbl_keys(self.usages[namespace] or {})
  table.sort(result)
  return result
end

---@param file string
---@return php_namespace_refactor.IndexEntry?
function Index:entry(file)
  return self.entries[file]
end

---@param file string
---@param entry php_namespace_refactor.IndexEntry
function Index:set(file, entry)
  self:remove(file)
  self.entries[file] = entry
  for _, namespace in ipairs(entry.imports) do
    self.usages[namespace] = self.usages[namespace] or {}
    self.usages[namespace][file] = true
  end
end

---(Re)indexes `file` from its contents.
---@param file string
---@param content string
---@param mtime? string
function Index:parse_and_add(file, content, mtime)
  local entry = M.parse(content)
  entry.mtime = mtime
  self:set(file, entry)
end

---@param file string
function Index:remove(file)
  local entry = self.entries[file]
  if not entry then
    return
  end

  for _, namespace in ipairs(entry.imports) do
    local users = self.usages[namespace]
    if users then
      users[file] = nil
      if next(users) == nil then
        self.usages[namespace] = nil
      end
    end
  end
  self.entries[file] = nil
end

---Removes every file under `directory`.
---@param directory string
function Index:remove_directory(directory)
  local prefix = directory:gsub('/+$', '') .. '/'
  for file in pairs(self.entries) do
    if vim.startswith(file, prefix) then
      self:remove(file)
    end
  end
end

---@return boolean ok
function Index:save()
  vim.fn.mkdir(vim.fs.dirname(self.path), 'p')
  local data = vim.json.encode({ version = M.VERSION, root = self.root, files = self.entries })
  return (fs.write_file(self.path, data))
end

---Loads the saved index, if any. A missing, unreadable or outdated file
---leaves the index empty.
function Index:load()
  local content = fs.read_file(self.path)
  local ok, data = pcall(vim.json.decode, content or '', { luanil = { object = true, array = true } })
  if not ok or type(data) ~= 'table' or data.version ~= M.VERSION or type(data.files) ~= 'table' then
    return
  end

  for file, entry in pairs(data.files) do
    if type(entry) == 'table' then
      self:set(file, { declares = entry.declares, imports = entry.imports or {}, mtime = entry.mtime })
    end
  end
end

---Brings the index up to date with the project files, asynchronously:
---files are parsed in chunks of M.CHUNK_SIZE, yielding to the event loop
---in between. Unchanged files (same mtime) are skipped and removed files
---dropped; the result is saved. Calls made while a build is running wait
---for that build.
---@param on_done? fun()
function Index:build(on_done)
  if on_done then
    table.insert(self.callbacks, on_done)
  end
  if self.building then
    return
  end
  self.building = true

  local list = files.list(self.root)
  local present = {}
  local i = 1

  local function finish()
    for file in pairs(self.entries) do
      if not present[file] then
        self:remove(file)
      end
    end
    self:save()
    self.building = false
    self.ready = true

    local callbacks = self.callbacks
    self.callbacks = {}
    for _, callback in ipairs(callbacks) do
      callback()
    end
  end

  local function step()
    local last = math.min(i + M.CHUNK_SIZE - 1, #list)
    for j = i, last do
      local file = list[j]
      present[file] = true
      local mtime = mtime_of(file)
      local entry = self.entries[file]
      if mtime and (not entry or entry.mtime ~= mtime) then
        local content = fs.read_file(file)
        if content then
          self:parse_and_add(file, content, mtime)
        end
      end
    end
    i = last + 1

    if i <= #list then
      vim.schedule(step)
    else
      finish()
    end
  end

  vim.schedule(step)
end

---@type table<string, php_namespace_refactor.Index>
local indexes = {}

---Directory the indexes are saved to.
---@return string
function M.cache_dir()
  return vim.fn.stdpath('cache') .. '/php-namespace-refactor'
end

---Index of the project at `root`, loaded from disk on first use.
---@param root string
---@return php_namespace_refactor.Index
function M.get(root)
  local index = indexes[root]
  if not index then
    index = M.new(root, ('%s/%s.json'):format(M.cache_dir(), vim.fn.sha256(root)))
    index:load()
    indexes[root] = index
  end
  return index
end

---Starts a build of the index of `file`'s project unless one already ran.
---@param file string
function M.ensure_built(file)
  local root = require('php-namespace-refactor.infra.composer').root(file)
  if not root then
    return
  end
  local index = M.get(root)
  if not index.ready then
    index:build()
  end
end

---Re-indexes a file after it was written.
---@param file string
function M.on_write(file)
  if file == '' or not require('php-namespace-refactor.domain.path').match_extension(file) then
    return
  end
  local root = require('php-namespace-refactor.infra.composer').root(file)
  if not root then
    return
  end

  local index = M.get(root)
  local content = fs.read_file(file)
  if content then
    index:parse_and_add(file, content, mtime_of(file))
    index:save()
  end
end

---Forgets the loaded indexes (not the saved files). Meant for tests.
function M._reset()
  indexes = {}
end

return M
