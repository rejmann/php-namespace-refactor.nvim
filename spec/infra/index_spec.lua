local assert = require('luassert')
local spy = require('luassert.spy')
local stub = require('luassert.stub')
local files = require('php-namespace-refactor.infra.files')
local index_module = require('php-namespace-refactor.infra.index')

---@return php_namespace_refactor.Index
local function new_index()
  return index_module.new('/project', vim.fn.tempname() .. '/index.json')
end

---Creates a composer project with the given files.
---@param contents table<string, string> Relative path → content
---@return string root
local function project(contents)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root) --[[@as string]]
  contents['composer.json'] = contents['composer.json'] or '{}'
  for relative, content in pairs(contents) do
    local file = root .. '/' .. relative
    vim.fn.mkdir(vim.fs.dirname(file), 'p')
    vim.fn.writefile(vim.split(content, '\n'), file)
  end
  return root
end

---@param index php_namespace_refactor.Index
local function build(index)
  local done = false
  index:build(function()
    done = true
  end)
  assert.is_true(vim.wait(5000, function()
    return done
  end))
end

-- Port of src/test/NamespaceIndex.test.ts
describe('index', function()
  local index ---@type php_namespace_refactor.Index

  before_each(function()
    index = new_index()
  end)

  -- Scenario 1 – when moving a class to another directory, all files that
  -- import it must be refactored. The index is the source of truth for
  -- finding them in O(1).
  describe('Scenario 1 – find all files affected by a move', function()
    it('files_using returns files that import the namespace', function()
      local file_a = '/src/Services/OrderService.php'
      local file_b = '/src/Http/OrderController.php'
      local ns = 'App\\Services\\Order'

      index:parse_and_add(file_a, 'namespace App\\Services;\nclass Order {}')
      index:parse_and_add(file_b, 'namespace App\\Http;\nuse ' .. ns .. ';\nclass OrderController {}')

      assert.are.same({ file_b }, index:files_using(ns))
    end)

    it('files_using returns a list even for a file importing its own namespace', function()
      local ns = 'App\\Services\\Order'

      index:parse_and_add('/src/Services/Order.php', 'namespace App\\Services;\nuse ' .. ns .. ';\nclass Order {}')

      assert.is_table(index:files_using(ns))
    end)

    it('returns multiple files that use the same namespace', function()
      local ns = 'App\\Domain\\Payment'
      local list = {
        '/src/Http/PaymentController.php',
        '/src/Jobs/ProcessPayment.php',
        '/src/Services/CheckoutService.php',
      }

      for _, file in ipairs(list) do
        index:parse_and_add(file, 'namespace App\\Http;\nuse ' .. ns .. ';\nclass Foo {}')
      end

      assert.are.same(list, index:files_using(ns))
    end)

    it('returns an empty list for an unknown namespace', function()
      assert.are.same({}, index:files_using('App\\Unknown\\Class'))
    end)
  end)

  -- After the move, the index must reflect the new state so subsequent
  -- operations do not find stale references.
  describe('Index update after move/delete', function()
    it('remove drops the file from usages', function()
      local file = '/src/Http/UserController.php'
      local ns = 'App\\Domain\\User'

      index:parse_and_add(file, 'namespace App\\Http;\nuse ' .. ns .. ';\nclass UserController {}')
      assert.are.equal(1, #index:files_using(ns))

      index:remove(file)
      assert.are.same({}, index:files_using(ns))
      assert.is_nil(index:entry(file))
    end)

    it('parse_and_add overwrites an existing entry without duplicating usages', function()
      local file = '/src/Http/UserController.php'
      local ns = 'App\\Domain\\User'

      index:parse_and_add(file, 'namespace App\\Http;\nuse ' .. ns .. ';\nclass UserController {}')
      index:parse_and_add(file, 'namespace App\\Http;\nuse ' .. ns .. ';\nclass UserController {}')

      assert.are.equal(1, #index:files_using(ns))
    end)

    it('parse_and_add updates the declared namespace when the file changes directory', function()
      local file = '/src/Services/Foo.php'

      index:parse_and_add(file, 'namespace App\\Services;\nclass Foo {}')
      index:parse_and_add(file, 'namespace App\\NewServices;\nclass Foo {}')

      assert.are.same({}, index:files_using('App\\Services\\Foo'))
      assert.are.equal('App\\NewServices', index:entry(file).declares)
    end)

    it('drops imports removed from the file', function()
      local file = '/src/Http/UserController.php'

      index:parse_and_add(file, 'namespace App\\Http;\nuse App\\Domain\\User;\n')
      index:parse_and_add(file, 'namespace App\\Http;\n')

      assert.are.same({}, index:files_using('App\\Domain\\User'))
    end)
  end)

  describe('Namespace and import extraction', function()
    it('extracts the declared namespace correctly', function()
      local consumer = '/src/Bar.php'
      index:parse_and_add('/src/Foo.php', 'namespace App\\Domain\\Foo;\nclass Foo {}')
      index:parse_and_add(consumer, 'namespace App;\nuse App\\Domain\\Foo\\Foo;\nclass Bar {}')

      assert.are.same({ consumer }, index:files_using('App\\Domain\\Foo\\Foo'))
    end)

    it('extracts multiple use statements from the same file', function()
      local file = '/src/Http/Controller.php'
      index:parse_and_add(
        file,
        'namespace App\\Http;\nuse App\\Domain\\User;\nuse App\\Domain\\Order;\nclass Controller {}'
      )

      assert.are.same({ file }, index:files_using('App\\Domain\\User'))
      assert.are.same({ file }, index:files_using('App\\Domain\\Order'))
    end)

    it('tracks aliased imports by FQCN, not by alias', function()
      local file = '/src/Http/Controller.php'
      index:parse_and_add(file, 'namespace App\\Http;\nuse App\\Domain\\User as UserEntity;\nclass Controller {}')

      assert.are.same({ file }, index:files_using('App\\Domain\\User'))
    end)

    it('does not throw for files without a namespace declaration', function()
      assert.has_no.errors(function()
        index:parse_and_add('/src/helpers.php', '<?php\nfunction helper() {}')
      end)
    end)
  end)

  describe('parse', function()
    it('strips a leading backslash from imports and the namespace', function()
      assert.are.same(
        { declares = 'App', imports = { 'App\\Domain\\User' } },
        index_module.parse('namespace \\App;\nuse \\App\\Domain\\User;\n')
      )
    end)

    it('ignores indented trait uses', function()
      assert.are.same({ imports = {} }, index_module.parse('class Foo {\n    use HasTimestamps;\n}'))
    end)
  end)

  describe('save / load', function()
    it('restores the entries and usages', function()
      index:parse_and_add('/src/A.php', 'namespace App;\nuse App\\Domain\\User;\n', '1.2')
      assert.is_true(index:save())

      local restored = index_module.new('/project', index.path)
      restored:load()

      assert.are.same({ '/src/A.php' }, restored:files_using('App\\Domain\\User'))
      assert.are.same(
        { declares = 'App', imports = { 'App\\Domain\\User' }, mtime = '1.2' },
        restored:entry('/src/A.php')
      )
    end)

    it('leaves the index empty when the saved file is missing or invalid', function()
      local restored = index_module.new('/project', vim.fn.tempname())
      restored:load()
      assert.is_nil(restored:entry('/src/A.php'))

      local path = vim.fn.tempname()
      vim.fn.writefile({ '{ broken' }, path)
      restored = index_module.new('/project', path)
      assert.has_no.errors(function()
        restored:load()
      end)
    end)
  end)

  describe('build', function()
    before_each(function()
      files.clear_cache()
    end)

    it('indexes every project file asynchronously and saves the result', function()
      local root = project({
        ['src/User.php'] = 'namespace App;\nclass User {}',
        ['src/Http/Controller.php'] = 'namespace App\\Http;\nuse App\\User;\n',
      })
      index = index_module.new(root, vim.fn.tempname() .. '/index.json')

      build(index)

      assert.is_true(index.ready)
      assert.are.same({ root .. '/src/Http/Controller.php' }, index:files_using('App\\User'))
      assert.is_not_nil(vim.uv.fs_stat(index.path))
    end)

    it('only re-parses files whose mtime changed and drops removed files', function()
      local root = project({
        ['src/A.php'] = 'use App\\User;',
        ['src/B.php'] = 'use App\\User;',
        ['src/C.php'] = 'use App\\User;',
      })
      index = index_module.new(root, vim.fn.tempname() .. '/index.json')
      build(index)

      vim.fn.writefile({ 'use App\\Order;' }, root .. '/src/B.php')
      vim.uv.fs_utime(root .. '/src/B.php', 1, 1)
      os.remove(root .. '/src/C.php')
      files.clear_cache()
      local parse = spy.on(index_module, 'parse')

      build(index)
      parse:revert()

      assert.spy(parse).was_called(1)

      assert.are.same({ root .. '/src/A.php' }, index:files_using('App\\User'))
      assert.are.same({ root .. '/src/B.php' }, index:files_using('App\\Order'))
    end)

    it('processes files in chunks', function()
      local contents = {}
      for i = 1, 5 do
        contents[('src/F%d.php'):format(i)] = 'use App\\User;'
      end
      index = index_module.new(project(contents), vim.fn.tempname() .. '/index.json')
      local chunk_size = index_module.CHUNK_SIZE
      index_module.CHUNK_SIZE = 2

      build(index)
      index_module.CHUNK_SIZE = chunk_size

      assert.are.equal(5, #index:files_using('App\\User'))
    end)

    it('lets concurrent callers wait for the running build', function()
      index = index_module.new(project({ ['src/A.php'] = 'use App\\User;' }), vim.fn.tempname() .. '/index.json')
      local calls = 0

      index:build(function()
        calls = calls + 1
      end)
      build(index)

      assert.are.equal(1, calls)
    end)
  end)

  describe('autocmds', function()
    local cache_dir

    before_each(function()
      index_module._reset()
      files.clear_cache()
      cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
      vim.g.loaded_php_namespace_refactor = nil
      dofile('plugin/php-namespace-refactor.lua')
    end)

    after_each(function()
      cache_dir:revert()
    end)

    it('builds the index when a PHP file of a composer project is opened', function()
      local root = project({ ['src/A.php'] = 'use App\\User;' })

      vim.cmd.edit(root .. '/src/A.php')
      vim.bo.filetype = 'php'

      local project_index = index_module.get(root)
      assert.is_true(vim.wait(5000, function()
        return project_index.ready
      end))
      assert.are.same({ root .. '/src/A.php' }, project_index:files_using('App\\User'))
      vim.cmd('bwipeout!')
    end)

    it('re-indexes a PHP file when it is written', function()
      local root = project({ ['src/A.php'] = '<?php' })
      vim.cmd.edit(root .. '/src/A.php')

      vim.api.nvim_buf_set_lines(0, -1, -1, false, { 'use App\\User;' })
      vim.cmd('silent write')

      assert.are.same({ root .. '/src/A.php' }, index_module.get(root):files_using('App\\User'))
      vim.cmd('bwipeout!')
    end)
  end)
end)
