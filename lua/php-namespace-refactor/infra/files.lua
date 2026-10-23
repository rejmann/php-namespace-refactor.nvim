---@mod php-namespace-refactor.infra.files Workspace file listing
---
---Lists the PHP files of a project with `rg`, `git ls-files` or a plain
---directory walk, whichever is available first.

local path = require('php-namespace-refactor.domain.path')

local M = {}

---Always ignored, on top of the configured `ignored_directories`.
M.DEFAULT_IGNORED_DIRECTORIES = { '/vendor/', '/var/', '/cache/' }

---How long a listing is reused, in milliseconds.
M.CACHE_TTL = 15000

---@alias php_namespace_refactor.FilesBackend 'rg'|'git'|'fs'

---@class php_namespace_refactor.ListOpts
---@field backends? php_namespace_refactor.FilesBackend[] Backends to try, in order (default: rg, git, fs)
---@field extensions? string[] Defaults to the configured additional_extensions
---@field ignored_directories? string[] Defaults to the configured ignored_directories

---@type table<string, { time: number, key: string, files: string[] }>
local cache = {}

---Monotonic time in milliseconds (vim.uv.now() doesn't advance within a
---synchronous call).
---@return number
local function now()
  return vim.uv.hrtime() / 1e6
end

---@param cmd string[]
---@param cwd string
---@return string[]? lines nil when the command fails
local function run(cmd, cwd)
  local ok, result = pcall(function()
    return vim.system(cmd, { cwd = cwd, text = true }):wait()
  end)
  if not ok or result.code ~= 0 then
    return nil
  end
  return vim.split(result.stdout or '', '\n', { trimempty = true })
end

---@type table<php_namespace_refactor.FilesBackend, fun(root: string, extensions: string[]): string[]?>
local backends = {
  rg = function(root, extensions)
    if vim.fn.executable('rg') ~= 1 then
      return nil
    end
    local cmd = { 'rg', '--files', '--no-messages' }
    for _, extension in ipairs(extensions) do
      vim.list_extend(cmd, { '--iglob', '*.' .. extension })
    end
    return run(cmd, root)
  end,

  git = function(root)
    if vim.fn.executable('git') ~= 1 then
      return nil
    end
    return run({ 'git', '-c', 'core.quotepath=off', 'ls-files', '--cached', '--others', '--exclude-standard' }, root)
  end,

  fs = function(root)
    local files = {}
    for name, type in vim.fs.dir(root, { depth = math.huge }) do
      if type == 'file' then
        table.insert(files, name)
      end
    end
    return files
  end,
}

---@param relative string
---@param ignored_directories string[]
---@return boolean
local function is_ignored(relative, ignored_directories)
  local candidate = '/' .. relative
  for _, directory in ipairs(ignored_directories) do
    if candidate:find(directory, 1, true) then
      return true
    end
  end
  return false
end

---Absolute paths of the files under `root` with one of the extensions,
---outside ignored directories, sorted. Ignored directories are matched
---against the path relative to `root` (with a leading `/`), so a project
---living under /var/www isn't ignored as a whole.
---@param root string
---@param opts? php_namespace_refactor.ListOpts
---@return string[]
function M.list(root, opts)
  opts = opts or {}
  local config = require('php-namespace-refactor.config').get()
  local extensions = path.normalize_extensions(opts.extensions or config.additional_extensions)
  local ignored_directories = vim.list_extend(
    vim.list_extend({}, M.DEFAULT_IGNORED_DIRECTORIES),
    opts.ignored_directories or config.ignored_directories
  )

  local key = vim.inspect({ opts.backends, extensions, ignored_directories })
  local cached = cache[root]
  if cached and cached.key == key and now() - cached.time < M.CACHE_TTL then
    return cached.files
  end

  local relative_files
  for _, name in ipairs(opts.backends or { 'rg', 'git', 'fs' }) do
    relative_files = backends[name](root, extensions)
    if relative_files then
      break
    end
  end

  local files = {}
  for _, relative in ipairs(relative_files or {}) do
    if path.match_extension(relative, extensions) and not is_ignored(relative, ignored_directories) then
      table.insert(files, root .. '/' .. relative)
    end
  end
  table.sort(files)

  cache[root] = { time = now(), key = key, files = files }
  return files
end

---Forgets the cached listing of `root`, or of every project.
---@param root? string
function M.clear_cache(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

return M
