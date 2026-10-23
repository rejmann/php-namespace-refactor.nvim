local assert = require('luassert')
local composer = require('php-namespace-refactor.infra.composer')

---Creates a project directory with the given composer.json content.
---@param content table|string
---@return string root
local function project(content)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/src/Domain', 'p')
  local json = type(content) == 'string' and content or vim.json.encode(content)
  vim.fn.writefile({ json }, root .. '/composer.json')
  return vim.uv.fs_realpath(root) --[[@as string]]
end

---@param psr4 table<string, string|string[]>
---@param dev_psr4? table<string, string|string[]>
local function autoload(psr4, dev_psr4)
  return composer.read(project({ autoload = { ['psr-4'] = psr4 }, ['autoload-dev'] = { ['psr-4'] = dev_psr4 or {} } }))
end

describe('composer', function()
  before_each(function()
    composer._reset()
  end)

  describe('read', function()
    it('reads the psr-4 entries of autoload and autoload-dev', function()
      local result = autoload({ ['App\\'] = 'src/' }, { ['App\\Tests\\'] = './tests' })

      table.sort(result.entries, function(a, b)
        return a.prefix < b.prefix
      end)
      assert.are.same({
        { prefix = 'App', directory = 'src', dev = false },
        { prefix = 'App\\Tests', directory = 'tests', dev = true },
      }, result.entries)
    end)

    it('expands a prefix mapped to several directories', function()
      local result = autoload({ ['App\\'] = { 'src/', 'lib/' } })

      assert.are.equal(2, #result.entries)
    end)

    it('returns no entries without a composer.json', function()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root, 'p')

      assert.are.same({ root = root, entries = {} }, composer.read(root))
    end)

    it('returns no entries for an invalid composer.json', function()
      assert.are.same({}, composer.read(project('{ not json')).entries)
    end)

    it('returns no entries when there is no psr-4 section', function()
      assert.are.same({}, composer.read(project({ name = 'acme/app' })).entries)
    end)

    it('caches the entries until composer.json changes', function()
      local root = project({ autoload = { ['psr-4'] = { ['App\\'] = 'src/' } } })
      local first = composer.read(root).entries

      assert.are.equal(first, composer.read(root).entries)

      vim.fn.writefile(
        { vim.json.encode({ autoload = { ['psr-4'] = { ['Acme\\'] = 'src/' } } }) },
        root .. '/composer.json'
      )
      vim.uv.fs_utime(root .. '/composer.json', 1, 1)

      assert.are.equal('Acme', composer.read(root).entries[1].prefix)
    end)
  end)

  describe('root', function()
    it('finds the closest directory with a composer.json', function()
      local root = project({})

      assert.are.equal(root, composer.root(root .. '/src/Domain/User.php'))
    end)
  end)

  -- Port of AutoloadPathResolver / NamespaceAutoloadMapper
  describe('namespace_from_directory', function()
    it('maps a sub-directory of a psr-4 directory', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal(
        'App\\Domain\\User',
        composer.namespace_from_directory(result.root .. '/src/Domain/User', result)
      )
    end)

    it('maps the psr-4 directory itself to the prefix', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal('App', composer.namespace_from_directory(result.root .. '/src', result))
    end)

    it('prefers the most specific directory', function()
      local result = autoload({ ['App\\'] = 'src/', ['Domain\\'] = 'src/Domain/' })

      assert.are.equal('Domain\\User', composer.namespace_from_directory(result.root .. '/src/Domain/User', result))
    end)

    it('falls back to autoload-dev', function()
      local result = autoload({ ['App\\'] = 'src/' }, { ['App\\Tests\\'] = 'tests/' })

      assert.are.equal('App\\Tests\\Unit', composer.namespace_from_directory(result.root .. '/tests/Unit', result))
    end)

    it('does not match a directory that merely starts with the same characters', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.is_nil(composer.namespace_from_directory(result.root .. '/srcfoo/Domain', result))
    end)

    it('maps an empty prefix to the global namespace', function()
      local result = autoload({ [''] = 'src/' })

      assert.are.equal('', composer.namespace_from_directory(result.root .. '/src', result))
      assert.are.equal('Domain', composer.namespace_from_directory(result.root .. '/src/Domain', result))
    end)

    it('maps the project root directory', function()
      local result = autoload({ ['App\\'] = '' })

      assert.are.equal('App\\src', composer.namespace_from_directory(result.root .. '/src', result))
      assert.are.equal('App', composer.namespace_from_directory(result.root, result))
    end)

    it('returns nil outside the project', function()
      local result = autoload({ ['App\\'] = '' })

      assert.is_nil(composer.namespace_from_directory('/elsewhere/src', result))
    end)

    it('finds the project of the directory when no autoload is given', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal('App\\Domain', composer.namespace_from_directory(result.root .. '/src/Domain'))
    end)
  end)

  -- Port of WorkspacePathResolver.getDirectoryFromNamespace
  describe('directory_from_namespace', function()
    it('maps a namespace to its directory', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal(
        result.root .. '/src/Domain/User',
        composer.directory_from_namespace('App\\Domain\\User', result)
      )
    end)

    it('maps the prefix itself to the psr-4 directory', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal(result.root .. '/src', composer.directory_from_namespace('App', result))
    end)

    it('prefers the longest prefix', function()
      local result = autoload({ ['App\\'] = 'src/', ['App\\Tests\\'] = 'tests/' })

      assert.are.equal(result.root .. '/tests/Unit', composer.directory_from_namespace('App\\Tests\\Unit', result))
    end)

    it('uses autoload-dev too', function()
      local result = autoload({ ['App\\'] = 'src/' }, { ['Tests\\'] = 'tests/' })

      assert.are.equal(result.root .. '/tests/Unit', composer.directory_from_namespace('Tests\\Unit', result))
    end)

    it('ignores leading and trailing backslashes', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal(result.root .. '/src/Domain', composer.directory_from_namespace('\\App\\Domain\\', result))
    end)

    it('does not match a namespace that merely starts with the same characters', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.is_nil(composer.directory_from_namespace('Application\\Domain', result))
    end)

    it('returns nil when no mapping applies', function()
      assert.is_nil(composer.directory_from_namespace('App\\Domain', autoload({})))
    end)
  end)

  -- Port of NamespaceCreator
  describe('class_namespace', function()
    it('builds the fully qualified class name of a file', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.same(
        { namespace = 'App\\Domain', class_name = 'User', full_namespace = 'App\\Domain\\User' },
        composer.class_namespace(result.root .. '/src/Domain/User.php', result)
      )
    end)

    it('uses the class name alone for a file outside every mapping', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.same(
        { class_name = 'User', full_namespace = 'User' },
        composer.class_namespace(result.root .. '/bin/User.php', result)
      )
    end)

    it('uses the class name alone for the global namespace', function()
      local result = autoload({ [''] = 'src/' })

      assert.are.same(
        { class_name = 'User', full_namespace = 'User' },
        composer.class_namespace(result.root .. '/src/User.php', result)
      )
    end)

    it('finds the project of the file when no autoload is given', function()
      local result = autoload({ ['App\\'] = 'src/' })

      assert.are.equal(
        'App\\Domain\\User',
        composer.class_namespace(result.root .. '/src/Domain/User.php').full_namespace
      )
    end)

    it('uses the class name alone outside a composer project', function()
      assert.are.equal('User', composer.class_namespace('/nonexistent/project/User.php').full_namespace)
    end)
  end)
end)
