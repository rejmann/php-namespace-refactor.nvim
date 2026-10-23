local assert = require('luassert')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local plugin = require('php-namespace-refactor')
local stub = require('luassert.stub')

---Copy of spec/fixtures/project in a temporary directory.
---@return string root
local function fixture()
  local root = vim.fn.tempname()
  vim.fn.system({ 'cp', '-R', 'spec/fixtures/project', root })
  return vim.uv.fs_realpath(root) --[[@as string]]
end

---@param file string
---@return string
local function read(file)
  return fs.read_text(file) --[[@as string]]
end

---@param text string
---@param needle string
local function assert_contains(text, needle)
  assert.is_truthy(text:find(needle, 1, true), ('expected %q in:\n%s'):format(needle, text))
end

---Runs plugin.move() and waits for the refactor to finish.
---@param old string
---@param new string
local function move(old, new)
  local done = false
  local ok, err = plugin.move(old, new, {
    on_done = function()
      done = true
    end,
  })
  assert.is_true(ok, err)
  assert.is_true(vim.wait(5000, function()
    return done
  end))
end

describe(':PhpNamespaceRefactor move', function()
  local cache_dir

  setup(function()
    vim.g.loaded_php_namespace_refactor = nil
    dofile('plugin/php-namespace-refactor.lua')
  end)

  before_each(function()
    files.clear_cache()
    index_module._reset()
    cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
  end)

  after_each(function()
    cache_dir:revert()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) ~= '' then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it('moves a class to another namespace and updates the project', function()
    local root = fixture()

    move(root .. '/src/Foo/Bar.php', root .. '/src/Baz/Bar.php')

    assert.is_nil(vim.uv.fs_stat(root .. '/src/Foo/Bar.php'))
    local bar = read(root .. '/src/Baz/Bar.php')
    assert_contains(bar, 'namespace App\\Baz;')
    assert_contains(bar, 'use App\\Foo\\Helper;')
    assert_contains(read(root .. '/src/Http/Controller.php'), 'use App\\Baz\\Bar;')
    assert_contains(read(root .. '/tests/BarTest.php'), 'use App\\Baz\\Bar;')
    assert_contains(read(root .. '/src/Foo/Consumer.php'), 'use App\\Baz\\Bar;')
  end)

  it('renames a class when its file is renamed', function()
    local root = fixture()

    move(root .. '/src/Foo/Bar.php', root .. '/src/Foo/Baz.php')

    assert_contains(read(root .. '/src/Foo/Baz.php'), 'class Baz\n')
    local controller = read(root .. '/src/Http/Controller.php')
    assert_contains(controller, 'use App\\Foo\\Baz;')
    assert_contains(controller, 'private Baz $bar')
    assert_contains(read(root .. '/src/Foo/Consumer.php'), 'private Baz $bar')
  end)

  it('moves a whole directory', function()
    local root = fixture()

    move(root .. '/src/Foo', root .. '/src/Domain/Foo')

    assert_contains(read(root .. '/src/Domain/Foo/Bar.php'), 'namespace App\\Domain\\Foo;')
    assert_contains(read(root .. '/src/Domain/Foo/Helper.php'), 'namespace App\\Domain\\Foo;')
    assert_contains(read(root .. '/src/Http/Controller.php'), 'use App\\Domain\\Foo\\Bar;')
  end)

  it('moves the current buffer with a single argument and keeps it writable', function()
    local root = fixture()
    vim.cmd.edit(root .. '/src/Foo/Bar.php')
    local bufnr = vim.api.nvim_get_current_buf()
    local notify = stub(vim, 'notify')

    vim.cmd('PhpNamespaceRefactor move ' .. vim.fn.fnameescape(root .. '/src/Baz/Bar.php'))
    local done = vim.wait(5000, function()
      return #notify.calls > 0
    end)
    notify:revert()

    assert.is_true(done)
    assert.are.equal(root .. '/src/Baz/Bar.php', vim.api.nvim_buf_get_name(bufnr))
    assert_contains(fs.buffer_text(bufnr), 'namespace App\\Baz;')
    assert.is_true(vim.bo[bufnr].modified)
    assert.has_no.errors(function()
      vim.cmd('silent write')
    end)
    assert_contains(fs.read_file(root .. '/src/Baz/Bar.php') --[[@as string]], 'namespace App\\Baz;')
    assert.are.equal(-1, vim.fn.bufnr('^' .. vim.fn.fnameescape(root .. '/src/Foo/Bar.php') .. '$'))
  end)

  it('refuses a missing source or an existing destination', function()
    local root = fixture()

    local ok, err = plugin.move(root .. '/src/Foo/Nope.php', root .. '/src/Baz/Nope.php')
    assert.is_false(ok)
    assert.matches('does not exist', err)

    ok, err = plugin.move(root .. '/src/Foo/Bar.php', root .. '/src/Foo/Helper.php')
    assert.is_false(ok)
    assert.matches('already exists', err)
  end)

  it('reports a wrong number of arguments', function()
    local notify = stub(vim, 'notify')

    vim.cmd('enew')
    vim.cmd('PhpNamespaceRefactor move only-one-arg-and-no-file.php')
    notify:revert()

    assert.stub(notify).was_called(1)
    assert.matches('usage', notify.calls[1].refs[1])
  end)

  it('completes file paths for both arguments', function()
    local result =
      plugin.complete('spec/fixtures/project/sr', 'PhpNamespaceRefactor move a.php spec/fixtures/project/sr')

    assert.are.same({ 'spec/fixtures/project/src/' }, result)
  end)
end)
