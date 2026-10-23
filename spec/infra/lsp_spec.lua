local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local lsp = require('php-namespace-refactor.infra.lsp')
local stub = require('luassert.stub')

---Copy of spec/fixtures/project in a temporary directory.
---@return string root
local function fixture()
  local root = vim.fn.tempname()
  vim.fn.system({ 'cp', '-R', 'spec/fixtures/project', root })
  return vim.uv.fs_realpath(root) --[[@as string]]
end

---@param client vim.lsp.Client
---@param method string
---@param params table
local function client_notify(client, method, params)
  if vim.fn.has('nvim-0.11') == 1 then
    client:notify(method, params)
  else
    ---@diagnostic disable-next-line: param-type-mismatch, missing-parameter
    client.notify(method, params)
  end
end

---@param client vim.lsp.Client
local function client_stop(client)
  if vim.fn.has('nvim-0.11') == 1 then
    client:stop(true)
  else
    ---@diagnostic disable-next-line: deprecated
    vim.lsp.stop_client(client.id, true)
  end
end

---Stops every client of this plugin, e.g. left over by other spec files.
local function stop_all()
  for _, client in ipairs(vim.lsp.get_clients({ name = lsp.NAME })) do
    client_stop(client)
  end
  assert.is_true(vim.wait(5000, function()
    return #vim.lsp.get_clients({ name = lsp.NAME }) == 0
  end))
end

---@param predicate fun(): boolean
local function wait_for(predicate)
  assert.is_true(vim.wait(5000, predicate))
end

describe('lsp', function()
  after_each(function()
    config._reset()
  end)

  describe('capabilities', function()
    it('registers every file operation for PHP files and folders', function()
      local file_operations = lsp.capabilities().workspace.fileOperations

      for _, operation in ipairs({ 'willRename', 'didRename', 'didCreate', 'didDelete' }) do
        assert.are.same({
          { scheme = 'file', pattern = { glob = '**/*.php', matches = 'file', options = { ignoreCase = true } } },
          { scheme = 'file', pattern = { glob = '**/*', matches = 'folder' } },
        }, file_operations[operation].filters)
      end
    end)

    it('covers the configured extensions', function()
      config.setup({ additional_extensions = { 'inc', 'class.php' } })

      assert.are.equal(
        '**/*.{php,inc,class.php}',
        lsp.capabilities().workspace.fileOperations.didRename.filters[1].pattern.glob
      )
    end)
  end)

  describe('server', function()
    ---@return vim.lsp.rpc.PublicClient server
    ---@return table on_exit stub
    local function server()
      local on_exit = stub()
      ---@diagnostic disable-next-line: missing-fields
      return lsp.server({ on_exit = on_exit }), on_exit
    end

    ---@param srv vim.lsp.rpc.PublicClient
    ---@param method string
    ---@return any err
    ---@return any result
    local function request(srv, method)
      local done, err, result = false, nil, nil
      srv.request(method, {}, function(e, r)
        done, err, result = true, e, r
      end)
      wait_for(function()
        return done
      end)
      return err, result
    end

    it('answers initialize with its capabilities', function()
      local _, result = request(server(), 'initialize')

      assert.are.equal(lsp.NAME, result.serverInfo.name)
      assert.is_table(result.capabilities.workspace.fileOperations.didRename)
    end)

    it('answers willRenameFiles without an edit', function()
      local err, result = request(server(), 'workspace/willRenameFiles')

      assert.is_nil(err)
      assert.are.equal(vim.NIL, result)
    end)

    it('rejects unknown requests', function()
      local err = request(server(), 'textDocument/hover')

      assert.are.equal(-32601, err.code)
    end)

    it('exits on the exit notification', function()
      local srv, on_exit = server()

      srv.notify('exit')

      assert.is_true(srv.is_closing())
      assert.stub(on_exit).was_called_with(0, 0)
    end)
  end)

  describe('attached to a composer project', function()
    local cache_dir, root, client

    setup(function()
      vim.g.loaded_php_namespace_refactor = nil
      dofile('plugin/php-namespace-refactor.lua')
    end)

    before_each(function()
      files.clear_cache()
      index_module._reset()
      cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
      stop_all()
      root = fixture()

      vim.cmd.edit(root .. '/src/Foo/Bar.php')
      vim.bo.filetype = 'php'
      wait_for(function()
        client = vim.lsp.get_clients({ name = lsp.NAME, bufnr = 0 })[1]
        return client ~= nil and client.initialized == true
      end)
    end)

    after_each(function()
      stop_all()
      cache_dir:revert()
      vim.cmd('silent! %bwipeout!')
    end)

    it('starts one client per project root', function()
      assert.are.equal(root, client.config.root_dir)

      vim.cmd.edit(root .. '/src/Foo/Helper.php')
      vim.bo.filetype = 'php'

      assert.are.equal(1, #vim.lsp.get_clients({ name = lsp.NAME }))
    end)

    it('refactors the project when an explorer reports a rename', function()
      -- What an explorer does: move the file, then notify the clients.
      vim.fn.mkdir(root .. '/src/Baz', 'p')
      assert(vim.uv.fs_rename(root .. '/src/Foo/Bar.php', root .. '/src/Baz/Bar.php'))
      client_notify(client, 'workspace/didRenameFiles', {
        files = {
          {
            oldUri = vim.uri_from_fname(root .. '/src/Foo/Bar.php'),
            newUri = vim.uri_from_fname(root .. '/src/Baz/Bar.php'),
          },
        },
      })

      wait_for(function()
        local text = fs.read_text(root .. '/src/Http/Controller.php') or ''
        return text:find('use App\\Baz\\Bar;', 1, true) ~= nil
      end)
      assert.matches('namespace App\\Baz;', fs.read_text(root .. '/src/Baz/Bar.php'), 1, true)
    end)

    it('indexes created files and forgets deleted directories', function()
      local index = index_module.get(root)
      local created = root .. '/src/Http/Other.php'
      assert(fs.write_file(created, '<?php\n\nnamespace App\\Http;\n\nuse App\\Foo\\Helper;\n'))

      client_notify(client, 'workspace/didCreateFiles', { files = { { uri = vim.uri_from_fname(created) } } })
      wait_for(function()
        return vim.tbl_contains(index:files_using('App\\Foo\\Helper'), created)
      end)

      client_notify(
        client,
        'workspace/didDeleteFiles',
        { files = { { uri = vim.uri_from_fname(root .. '/src/Http') } } }
      )
      wait_for(function()
        return not vim.tbl_contains(index:files_using('App\\Foo\\Helper'), created)
      end)
    end)
  end)

  it('does not start outside a composer project', function()
    local file = vim.fn.tempname() .. '.php'
    vim.cmd.edit(file)

    assert.is_nil(lsp.start(0))
    vim.cmd('bwipeout!')
  end)
end)
