local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local file_move = require('php-namespace-refactor.app.operations.file_move')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local resolver = require('php-namespace-refactor.app.services.directory_moved_files_resolver')
local stub = require('luassert.stub')

---Creates a composer project (`App\` → `src/`) with the given files.
---@param contents table<string, string> Relative path → content
---@return string root
local function project(contents)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root) --[[@as string]]
  assert(fs.write_file(root .. '/composer.json', '{"autoload": {"psr-4": {"App\\\\": "src/"}}}'))
  for relative, content in pairs(contents) do
    local file = root .. '/' .. relative
    vim.fn.mkdir(vim.fs.dirname(file), 'p')
    assert(fs.write_file(file, content))
  end
  return root
end

---Moves a file or directory on disk.
---@param from string
---@param to string
local function rename(from, to)
  vim.fn.mkdir(vim.fs.dirname(to), 'p')
  assert(vim.uv.fs_rename(from, to))
end

---@param file string
---@return string
local function read(file)
  return fs.read_file(file) --[[@as string]]
end

describe('directory_moved_files_resolver', function()
  it('expands a moved directory into one move per file', function()
    local root = project({ ['src/Sales/Order.php'] = '', ['src/Sales/Line/Item.php'] = '' })

    local moves = resolver.execute({ { old = root .. '/src/Domain', new = root .. '/src/Sales' } })

    assert.are.same({
      { old = root .. '/src/Domain/Line/Item.php', new = root .. '/src/Sales/Line/Item.php' },
      { old = root .. '/src/Domain/Order.php', new = root .. '/src/Sales/Order.php' },
    }, moves)
  end)

  it('keeps file moves and drops duplicates', function()
    local move = { old = '/a/Foo.php', new = '/b/Foo.php' }

    assert.are.same({ move }, resolver.execute({ move, { old = '/a/Foo.php', new = '/b/Foo.php' } }))
  end)

  it('falls back to loaded buffers for a directory that is not on disk', function()
    local root = project({})
    local bufnr = vim.fn.bufadd(root .. '/src/Sales/Order.php')
    vim.fn.bufload(bufnr)

    local moves = resolver.execute({ { old = root .. '/src/Domain', new = root .. '/src/Sales' } })
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.are.same({ { old = root .. '/src/Domain/Order.php', new = root .. '/src/Sales/Order.php' } }, moves)
  end)
end)

describe('file_move', function()
  local cache_dir

  before_each(function()
    files.clear_cache()
    index_module._reset()
    config._reset()
    cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
  end)

  after_each(function()
    cache_dir:revert()
    config._reset()
  end)

  it('refactors a moved file, its references and its imports', function()
    local root = project({
      ['src/Domain/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order\n{\n    private Customer $customer;\n}\n',
      ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer {}\n',
      ['src/Http/OrderController.php'] = '<?php\n\nnamespace App\\Http;\n\nuse App\\Domain\\Order;\n\nclass OrderController {}\n',
    })
    rename(root .. '/src/Domain/Order.php', root .. '/src/Sales/Order.php')

    file_move.execute({ { old = root .. '/src/Domain/Order.php', new = root .. '/src/Sales/Order.php' } })

    assert.are.equal(
      '<?php\n\nnamespace App\\Sales;\n\nuse App\\Domain\\Customer;\n\nclass Order\n{\n    private Customer $customer;\n}\n',
      read(root .. '/src/Sales/Order.php')
    )
    assert.matches('use App\\Sales\\Order;', read(root .. '/src/Http/OrderController.php'), 1, true)
    assert.are.same({ root .. '/src/Sales/Order.php' }, index_module.get(root):files_using('App\\Domain\\Customer'))
  end)

  it('does not import old siblings when auto_import_namespace is off', function()
    local root = project({
      ['src/Domain/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order\n{\n    private Customer $customer;\n}\n',
      ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer {}\n',
    })
    config.setup({ auto_import_namespace = false })
    rename(root .. '/src/Domain/Order.php', root .. '/src/Sales/Order.php')

    file_move.execute({ { old = root .. '/src/Domain/Order.php', new = root .. '/src/Sales/Order.php' } })

    assert.is_nil(read(root .. '/src/Sales/Order.php'):find('use ', 1, true))
  end)

  it('refactors every PHP file of a moved directory and skips other files', function()
    local root = project({
      ['src/Domain/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order {}\n',
      ['src/Domain/Line/Item.php'] = '<?php\n\nnamespace App\\Domain\\Line;\n\nclass Item {}\n',
      ['src/Domain/notes.txt'] = 'namespace App\\Domain;',
    })
    rename(root .. '/src/Domain', root .. '/src/Sales')

    file_move.execute({ { old = root .. '/src/Domain', new = root .. '/src/Sales' } })

    assert.matches('namespace App\\Sales;', read(root .. '/src/Sales/Order.php'), 1, true)
    assert.matches('namespace App\\Sales\\Line;', read(root .. '/src/Sales/Line/Item.php'), 1, true)
    assert.are.equal('namespace App\\Domain;', read(root .. '/src/Sales/notes.txt'))
  end)

  it('reports a failing move and goes on with the next one', function()
    local root = project({ ['src/Sales/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order {}\n' })
    local updater = require('php-namespace-refactor.app.services.namespace_batch_updater')
    local original = updater.execute
    local execute = stub(updater, 'execute').invokes(function(old, new)
      if old:find('Broken', 1, true) then
        error('boom')
      end
      return original(old, new)
    end)
    local notify = stub(vim, 'notify')

    file_move.execute({
      { old = root .. '/src/Broken.php', new = root .. '/src/Broken2.php' },
      { old = root .. '/src/Domain/Order.php', new = root .. '/src/Sales/Order.php' },
    })
    execute:revert()
    notify:revert()

    assert.stub(notify).was_called(1)
    assert.matches('namespace App\\Sales;', read(root .. '/src/Sales/Order.php'), 1, true)
  end)

  it('processes queued batches in order', function()
    local order = {}
    local execute = stub(file_move, 'execute').invokes(function(moves)
      table.insert(order, moves[1].new)
    end)
    local done = false

    file_move.enqueue({ { old = '/a', new = '/1' } })
    file_move.enqueue({ { old = '/a', new = '/2' } }, function()
      done = true
    end)
    assert.is_true(vim.wait(1000, function()
      return done
    end))
    execute:revert()

    assert.are.same({ '/1', '/2' }, order)
  end)
end)
