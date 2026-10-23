---@mod php-namespace-refactor.app.operations.file_move File move operation
---
---Port of FileMoveOperation and FileRenameHandler: refactors the project
---after files or directories were moved on disk. Moves are queued and
---processed one batch at a time, in order.

local composer = require('php-namespace-refactor.infra.composer')
local config = require('php-namespace-refactor.config')
local directory_moved_files_resolver = require('php-namespace-refactor.app.services.directory_moved_files_resolver')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local import_remover = require('php-namespace-refactor.app.services.import_remover')
local missing_class_importer = require('php-namespace-refactor.app.services.missing_class_importer')
local namespace_batch_updater = require('php-namespace-refactor.app.services.namespace_batch_updater')
local path = require('php-namespace-refactor.domain.path')

local M = {}

---Keeps the namespace index of the project in line with a moved file.
---@param move php_namespace_refactor.FileMove
local function update_index(move)
  local root = composer.root(move.new)
  if not root then
    return
  end
  files.clear_cache(root)

  local index = require('php-namespace-refactor.infra.index').get(root)
  index:remove(move.old)
  local text = fs.read_text(move.new)
  if text then
    index:parse_and_add(move.new, text)
  end
  index:save()
end

---Refactors the project for each moved PHP file (directories are expanded
---into the files they contain), synchronously.
---@param moves php_namespace_refactor.FileMove[] Already moved on disk
function M.execute(moves)
  local cfg = config.get()

  for _, move in ipairs(directory_moved_files_resolver.execute(moves)) do
    if path.match_extension(move.old) and path.match_extension(move.new) then
      local ok, err = pcall(function()
        namespace_batch_updater.execute(move.old, move.new)
        if cfg.auto_import_namespace then
          missing_class_importer.execute(move.old, move.new)
        end
        import_remover.execute(move.new)
        update_index(move)
      end)
      if not ok then
        vim.notify(('php-namespace-refactor: failed to refactor %s: %s'):format(move.new, err), vim.log.levels.ERROR)
      end
    end
  end
end

---@type { moves: php_namespace_refactor.FileMove[], on_done?: fun() }[]
local queue = {}
local running = false

local function process()
  local batch = table.remove(queue, 1)
  if not batch then
    running = false
    return
  end

  -- A failure must not leave the queue stuck in the running state.
  local ok, err = pcall(M.execute, batch.moves)
  if not ok then
    vim.notify('php-namespace-refactor: ' .. tostring(err), vim.log.levels.ERROR)
  end
  if batch.on_done then
    batch.on_done()
  end
  vim.schedule(process)
end

---Queues moves to be refactored after the ones already queued, each batch
---on its own event loop iteration.
---@param moves php_namespace_refactor.FileMove[]
---@param on_done? fun() Called once this batch was processed
function M.enqueue(moves, on_done)
  table.insert(queue, { moves = moves, on_done = on_done })
  if not running then
    running = true
    vim.schedule(process)
  end
end

return M
