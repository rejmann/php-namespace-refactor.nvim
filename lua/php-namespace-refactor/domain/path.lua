---@mod php-namespace-refactor.domain.path Path resolution
---
---Class names, extensions and directories derived from file paths. Every
---function taking `extensions` falls back to the configured
---`additional_extensions` when it is omitted.

local M = {}

M.DEFAULT_EXTENSION = 'php'

---Lowercases, strips leading dots, drops empty entries and deduplicates,
---always keeping `php` first.
---@param extensions string[]
---@return string[]
function M.normalize_extensions(extensions)
  local normalized = { M.DEFAULT_EXTENSION }
  local seen = { [M.DEFAULT_EXTENSION] = true }

  for _, extension in ipairs(extensions) do
    extension = vim.trim(extension):lower():gsub('^%.+', '')
    if extension ~= '' and not seen[extension] then
      seen[extension] = true
      table.insert(normalized, extension)
    end
  end

  return normalized
end

---@param extensions? string[]
---@return string[]
local function sorted_extensions(extensions)
  extensions = extensions or require('php-namespace-refactor.config').get().additional_extensions
  local normalized = M.normalize_extensions(extensions)
  table.sort(normalized, function(a, b)
    return #a > #b
  end)
  return normalized
end

---Returns the configured extension (including the leading dot) that
---`file_name` ends with, matching the longest configured suffix first so a
---compound extension like `class.php` is never shadowed by the plain `php`
---entry. Matching ignores case; the suffix keeps the file name's case.
---@param file_name string
---@param extensions? string[]
---@return string?
function M.match_extension(file_name, extensions)
  local lower_file_name = file_name:lower()

  for _, extension in ipairs(sorted_extensions(extensions)) do
    local suffix = '.' .. extension
    if vim.endswith(lower_file_name, suffix) then
      return file_name:sub(#file_name - #suffix + 1)
    end
  end

  return nil
end

---File name without its configured extension, e.g. `Color` for
---`/src/Color.enum.php` when `enum.php` is configured.
---@param path string
---@param extensions? string[]
---@return string
function M.class_name_from_path(path, extensions)
  local file_name = vim.fs.basename(path)
  local extension = M.match_extension(file_name, extensions)

  if not extension then
    return file_name
  end

  return file_name:sub(1, #file_name - #extension)
end

---Configured extension of the file, falling back to its last dot segment.
---@param path string
---@param extensions? string[]
---@return string extension With the leading dot, or '' when there is none
function M.extension_from_path(path, extensions)
  local file_name = vim.fs.basename(path)
  local extension = M.match_extension(file_name, extensions)
  if extension then
    return extension
  end

  return file_name:match('^.+(%.[^.]*)$') or ''
end

---@param path string
---@return string
function M.directory_from_path(path)
  return vim.fs.dirname(path)
end

---Path relative to `root`, without a leading slash. Paths outside `root`
---are returned unchanged.
---@param path string
---@param root string
---@return string
function M.relative_path(path, root)
  root = root:gsub('/+$', '')
  if root ~= '' and vim.startswith(path, root .. '/') then
    return path:sub(#root + 2)
  end
  return path
end

return M
