local assert = require('luassert')
local class_rename = require('php-namespace-refactor.app.operations.class_rename')
local config = require('php-namespace-refactor.config')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local namespace_rename = require('php-namespace-refactor.app.operations.namespace_rename')
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

---Opens `file` with the cursor on the first line matching `pattern`.
---@param file string
---@param pattern string
local function edit_at(file, pattern)
  vim.cmd.edit(file)
  vim.fn.cursor(vim.fn.search(pattern), 1)
end

---Stubs vim.ui.input to answer with each of `answers` in turn.
---@param answers (string|false)[] false cancels
---@return table input The stub
local function answer(answers)
  local i = 0
  return stub(vim.ui, 'input').invokes(function(_, on_confirm)
    i = i + 1
    local value = answers[i]
    on_confirm(value or nil)
  end)
end

---Runs plugin.rename() and waits for the refactor to finish.
local function rename_and_wait()
  local done = false
  plugin.rename({
    on_done = function()
      done = true
    end,
  })
  assert.is_true(vim.wait(5000, function()
    return done
  end))
end

-- Port of src/test/ClassRenameOperation.test.ts
--
-- https://github.com/rejmann/php-namespace-refactor/issues/72
--
-- The renamed file must keep the full configured extension (e.g. `.class.php`),
-- not just the last `.php` segment.
describe('class_rename.target', function()
  after_each(function()
    config._reset()
  end)

  it('keeps the ".class.php" extension when renaming Old.class.php to New', function()
    config.setup({ additional_extensions = { 'class.php', 'trait.php', 'enum.php', 'interface.php' } })

    assert.are.equal('/src/New.class.php', class_rename.target('/src/Old.class.php', 'New'))
  end)

  it('keeps a plain ".php" extension when no compound extension is configured', function()
    assert.are.equal('/src/New.php', class_rename.target('/src/Old.php', 'New'))
  end)
end)

describe('namespace_rename.target', function()
  it('maps the namespace to its psr-4 directory, keeping the file name', function()
    local root = fixture()

    assert.are.equal(
      root .. '/src/Domain/Sales/Bar.php',
      namespace_rename.target(root .. '/src/Foo/Bar.php', 'App\\Domain\\Sales')
    )
  end)

  it('reports a namespace without a psr-4 mapping', function()
    local root = fixture()

    local target, err = namespace_rename.target(root .. '/src/Foo/Bar.php', 'Vendor\\Lib')

    assert.is_nil(target)
    assert.matches('no psr%-4 mapping', err)
  end)
end)

describe('rename', function()
  local cache_dir, input, notify

  setup(function()
    vim.g.loaded_php_namespace_refactor = nil
    dofile('plugin/php-namespace-refactor.lua')
  end)

  before_each(function()
    files.clear_cache()
    index_module._reset()
    config._reset()
    cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
    notify = stub(vim, 'notify')
  end)

  after_each(function()
    cache_dir:revert()
    notify:revert()
    if input then
      input:revert()
      input = nil
    end
    config._reset()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) ~= '' then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it('renames the class under the cursor, its file and its references', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', '^class Bar')
    input = answer({ 'Baz' })

    rename_and_wait()

    assert.is_nil(vim.uv.fs_stat(root .. '/src/Foo/Bar.php'))
    assert_contains(read(root .. '/src/Foo/Baz.php'), 'class Baz\n')
    assert_contains(read(root .. '/src/Http/Controller.php'), 'use App\\Foo\\Baz;')
    assert.are.equal(root .. '/src/Foo/Baz.php', vim.api.nvim_buf_get_name(0))
    assert.are.same({ prompt = 'New class name: ', default = 'Bar' }, input.calls[1].refs[1])
  end)

  it('moves the class to the directory of a new namespace', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', '^namespace')
    input = answer({ 'App\\Domain' })

    rename_and_wait()

    assert_contains(read(root .. '/src/Domain/Bar.php'), 'namespace App\\Domain;')
    assert_contains(read(root .. '/src/Http/Controller.php'), 'use App\\Domain\\Bar;')
    assert.are.same({ prompt = 'New namespace: ', default = 'App\\Foo' }, input.calls[1].refs[1])
  end)

  it('asks again after an invalid name, showing the error', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', '^class Bar')
    input = answer({ '2Bad', 'Good' })

    rename_and_wait()

    assert.stub(input).was_called(2)
    assert.are.equal('2Bad', input.calls[2].refs[1].default)
    assert.matches('cannot start with a number', notify.calls[1].refs[1])
    assert.is_not_nil(vim.uv.fs_stat(root .. '/src/Foo/Good.php'))
  end)

  it('does nothing when cancelled or given the same name', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', '^class Bar')
    input = answer({ false, 'Bar' })

    plugin.rename()
    plugin.rename()

    assert.is_not_nil(vim.uv.fs_stat(root .. '/src/Foo/Bar.php'))
    assert.stub(notify).was_not_called()
  end)

  it('refuses when rename is disabled', function()
    local root = fixture()
    config.setup({ rename = false })
    edit_at(root .. '/src/Foo/Bar.php', '^class Bar')
    input = answer({ 'Baz' })

    plugin.rename()

    assert.stub(input).was_not_called()
    assert.matches('disabled', notify.calls[1].refs[1])
  end)

  it('asks for the cursor to be on a declaration', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', 'return')
    input = answer({ 'Baz' })

    plugin.rename()

    assert.stub(input).was_not_called()
    assert.matches('cursor', notify.calls[1].refs[1])
  end)

  it('reports a namespace without a psr-4 mapping', function()
    local root = fixture()
    edit_at(root .. '/src/Foo/Bar.php', '^namespace')
    input = answer({ 'Vendor\\Lib' })

    plugin.rename()

    assert.matches('no psr%-4 mapping', notify.calls[1].refs[1])
    assert.is_not_nil(vim.uv.fs_stat(root .. '/src/Foo/Bar.php'))
  end)

  it('is available as a subcommand and a <Plug> mapping', function()
    assert.is_not_nil(plugin.subcommands.rename)
    assert.are_not.equal('', vim.fn.maparg('<Plug>(PhpNamespaceRefactorRename)', 'n'))
  end)
end)
