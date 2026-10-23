local assert = require('luassert')
local files = require('php-namespace-refactor.infra.files')

---Creates a project with the given relative files.
---@param relative_files string[]
---@return string root
local function project(relative_files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root) --[[@as string]]
  for _, relative in ipairs(relative_files) do
    local file = root .. '/' .. relative
    vim.fn.mkdir(vim.fs.dirname(file), 'p')
    vim.fn.writefile({ '<?php' }, file)
  end
  return root
end

---@param root string
---@param list string[]
---@return string[]
local function relative(root, list)
  return vim.tbl_map(function(file)
    return file:sub(#root + 2)
  end, list)
end

local layout = {
  'composer.json',
  'src/Domain/User.php',
  'src/Domain/Color.enum.php',
  'src/Domain/Legacy.PHP',
  'src/Domain/notes.txt',
  'vendor/acme/lib/Foo.php',
  'var/cache/Container.php',
  'build/Generated.php',
  'tests/UserTest.php',
}

local opts = { extensions = { 'php' }, ignored_directories = { '/build/' } }

describe('files.list', function()
  before_each(function()
    files.clear_cache()
  end)

  for _, backend in ipairs({ 'fs', 'git', 'rg' }) do
    describe('with the ' .. backend .. ' backend', function()
      local available = backend == 'fs' or vim.fn.executable(backend) == 1

      local test = available and it or pending
      test('lists files with a configured extension outside ignored directories', function()
        local root = project(layout)
        if backend == 'git' then
          vim.system({ 'git', 'init', '-q' }, { cwd = root }):wait()
        end

        local result = files.list(root, vim.tbl_extend('force', opts, { backends = { backend } }))

        assert.are.same({
          'src/Domain/Color.enum.php',
          'src/Domain/Legacy.PHP',
          'src/Domain/User.php',
          'tests/UserTest.php',
        }, relative(root, result))
      end)
    end)
  end

  it('falls back to another backend when one fails', function()
    -- Not a git repository, so `git ls-files` fails.
    local root = project({ 'src/User.php' })

    assert.are.same({ 'src/User.php' }, relative(root, files.list(root, { backends = { 'git', 'fs' } })))
  end)

  it('always ignores the default directories, even when the config replaces them', function()
    local root = project({ 'src/User.php', 'vendor/Foo.php' })

    local result = files.list(root, { backends = { 'fs' }, ignored_directories = {} })

    assert.are.same({ 'src/User.php' }, relative(root, result))
  end)

  it('matches ignored directories relative to the project root', function()
    local root = project({ 'var/www/app/src/User.php' })
    local app = root .. '/var/www/app'

    assert.are.same({ 'src/User.php' }, relative(app, files.list(app, { backends = { 'fs' } })))
  end)

  it('reads extensions and ignored directories from the config by default', function()
    local config = require('php-namespace-refactor.config')
    config.setup({ additional_extensions = { 'inc' }, ignored_directories = { '/legacy/' } })
    local root = project({ 'src/User.php', 'src/helpers.inc', 'legacy/Old.php' })

    local result = files.list(root, { backends = { 'fs' } })
    config._reset()

    assert.are.same({ 'src/User.php', 'src/helpers.inc' }, relative(root, result))
  end)

  it('caches the listing until cleared', function()
    local root = project({ 'src/User.php' })
    local first = files.list(root, { backends = { 'fs' } })
    vim.fn.writefile({ '<?php' }, root .. '/src/Order.php')

    assert.are.equal(first, files.list(root, { backends = { 'fs' } }))

    files.clear_cache(root)
    assert.are.same({ 'src/Order.php', 'src/User.php' }, relative(root, files.list(root, { backends = { 'fs' } })))
  end)

  it('does not reuse a listing made with other options', function()
    local root = project({ 'src/User.php', 'src/helpers.inc' })
    files.list(root, { backends = { 'fs' } })

    local result = files.list(root, { backends = { 'fs' }, extensions = { 'inc' } })

    assert.are.same({ 'src/User.php', 'src/helpers.inc' }, relative(root, result))
  end)
end)
