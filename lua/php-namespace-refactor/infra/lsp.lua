---@mod php-namespace-refactor.infra.lsp In-process language server
---
---File explorers (neo-tree, oil, nvim-tree, snacks, ...) tell every LSP
---client about the files they create, rename and delete. This in-process
---server registers for those `workspace/*Files` notifications in each
---composer project, so moving a PHP file or directory in an explorer
---refactors the project like `:PhpNamespaceRefactor move` does. It offers
---no other capability.

local M = {}

M.NAME = 'php-namespace-refactor'

---@param file string
---@return php_namespace_refactor.Index?
local function index_of(file)
  local root = require('php-namespace-refactor.infra.composer').root(file)
  if not root then
    return nil
  end
  require('php-namespace-refactor.infra.files').clear_cache(root)
  return require('php-namespace-refactor.infra.index').get(root)
end

---Files with a configured extension at or under `file`.
---@param file string
---@return string[]
local function php_files_at(file)
  local path = require('php-namespace-refactor.domain.path')
  local stat = vim.uv.fs_stat(file)
  if stat and stat.type == 'directory' then
    local result = {}
    for name, type in vim.fs.dir(file, { depth = math.huge }) do
      if type == 'file' and path.match_extension(name) then
        table.insert(result, file .. '/' .. name)
      end
    end
    return result
  end
  return path.match_extension(file) and { file } or {}
end

---@param params { files: { uri?: string, oldUri?: string, newUri?: string }[] }
---@param key 'uri'|'oldUri'|'newUri'
---@return string[]
local function paths(params, key)
  return vim.tbl_map(function(file)
    return vim.uri_to_fname(file[key])
  end, params.files or {})
end

---@type table<string, fun(params: any)>
local notifications = {
  ['workspace/didRenameFiles'] = function(params)
    local moves = vim.tbl_map(function(file)
      return { old = vim.uri_to_fname(file.oldUri), new = vim.uri_to_fname(file.newUri) }
    end, params.files or {})
    if #moves > 0 then
      require('php-namespace-refactor.app.operations.file_move').enqueue(moves)
    end
  end,

  -- Port of FileCreatedSubscriber.
  ['workspace/didCreateFiles'] = function(params)
    for _, created in ipairs(paths(params, 'uri')) do
      local index = index_of(created)
      if index then
        for _, file in ipairs(php_files_at(created)) do
          local text = require('php-namespace-refactor.infra.fs').read_file(file)
          if text then
            index:parse_and_add(file, text)
          end
        end
        index:save()
      end
    end
  end,

  -- Port of FileDeletedSubscriber.
  ['workspace/didDeleteFiles'] = function(params)
    for _, deleted in ipairs(paths(params, 'uri')) do
      local index = index_of(deleted)
      if index then
        index:remove(deleted)
        index:remove_directory(deleted)
        index:save()
      end
    end
  end,
}

---Registration options matching PHP files and folders.
---@return table
local function file_operation_registration()
  local extensions = require('php-namespace-refactor.domain.path').normalize_extensions(
    require('php-namespace-refactor.config').get().additional_extensions
  )
  local glob = #extensions == 1 and ('**/*.' .. extensions[1]) or ('**/*.{' .. table.concat(extensions, ',') .. '}')

  return {
    filters = {
      { scheme = 'file', pattern = { glob = glob, matches = 'file', options = { ignoreCase = true } } },
      { scheme = 'file', pattern = { glob = '**/*', matches = 'folder' } },
    },
  }
end

---@return table
function M.capabilities()
  local registration = file_operation_registration()
  return {
    workspace = {
      fileOperations = {
        -- Some explorers only send the will* request: answer it (with no
        -- edit) so they go on to send did*, which does the work.
        willRename = registration,
        didRename = registration,
        didCreate = registration,
        didDelete = registration,
      },
    },
  }
end

---@type table<string, fun(params: any): any>
local requests = {
  initialize = function()
    return { capabilities = M.capabilities(), serverInfo = { name = M.NAME } }
  end,
  shutdown = function()
    return vim.NIL
  end,
  ['workspace/willRenameFiles'] = function()
    return vim.NIL
  end,
}

---The `cmd` of the client: an in-process server.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@return vim.lsp.rpc.PublicClient
function M.server(dispatchers)
  local closing = false
  local last_id = 0

  local function close()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 0)
    end
  end

  return {
    request = function(method, params, callback, notify_reply_callback)
      last_id = last_id + 1
      local id = last_id
      local handler = requests[method]
      local ok, result = true, nil
      if handler then
        ok, result = pcall(handler, params)
      end
      vim.schedule(function()
        if not handler then
          callback({ code = -32601, message = 'Method not found: ' .. method })
        elseif not ok then
          callback({ code = -32603, message = tostring(result) })
        else
          callback(nil, result)
        end
        if notify_reply_callback then
          notify_reply_callback(id)
        end
      end)
      return true, id
    end,

    notify = function(method, params)
      if method == 'exit' then
        close()
      elseif notifications[method] then
        vim.schedule(function()
          local ok, err = pcall(notifications[method], params)
          if not ok then
            vim.notify(('php-namespace-refactor: %s failed: %s'):format(method, err), vim.log.levels.ERROR)
          end
        end)
      end
      return true
    end,

    is_closing = function()
      return closing
    end,

    terminate = close,
  }
end

---Attaches the server to `bufnr` when it belongs to a composer project (one
---client per project root).
---@param bufnr integer
---@return integer? client_id
function M.start(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = file ~= '' and require('php-namespace-refactor.infra.composer').root(file) or nil
  if not root then
    return nil
  end

  return vim.lsp.start({
    name = M.NAME,
    cmd = M.server,
    root_dir = root,
    workspace_folders = { { uri = vim.uri_from_fname(root), name = root } },
  }, {
    bufnr = bufnr,
    -- One client per project: newer defaults may reuse a client of another
    -- root through its workspace folders.
    reuse_client = function(client, config)
      return client.name == config.name and client.config.root_dir == config.root_dir
    end,
  })
end

return M
