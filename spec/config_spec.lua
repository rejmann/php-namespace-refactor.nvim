local assert = require('luassert')
local stub = require('luassert.stub')
local config = require('php-namespace-refactor.config')

describe('config', function()
  before_each(function()
    config._reset()
    vim.g.php_namespace_refactor = nil
  end)

  describe('get', function()
    it('returns the defaults when nothing is configured', function()
      assert.are.same(config.defaults, config.get())
    end)

    it('reads options from vim.g.php_namespace_refactor', function()
      vim.g.php_namespace_refactor = { rename = false }

      local resolved = config.get()

      assert.is_false(resolved.rename)
      assert.is_true(resolved.auto_import_namespace)
    end)

    it('gives setup() options precedence over vim.g', function()
      vim.g.php_namespace_refactor = { rename = false, remove_unused_imports = false }
      config.setup({ rename = true })

      local resolved = config.get()

      assert.is_true(resolved.rename)
      assert.is_false(resolved.remove_unused_imports)
    end)

    it('replaces list options instead of merging them index by index', function()
      config.setup({ ignored_directories = { '/build/' } })

      assert.are.same({ '/build/' }, config.get().ignored_directories)
    end)

    it('does not let callers mutate the defaults', function()
      config.get().ignored_directories[1] = '/changed/'

      assert.are.same({ '/vendor/', '/var/', '/cache/' }, config.defaults.ignored_directories)
    end)

    it('falls back to the defaults and reports an invalid vim.g config', function()
      vim.g.php_namespace_refactor = { rename = 'yes' }
      local notify = stub(vim, 'notify')

      local resolved = config.get()
      notify:revert()

      assert.are.same(config.defaults, resolved)
      assert.stub(notify).was_called(1)
      assert.matches('rename', notify.calls[1].refs[1])
    end)
  end)

  describe('setup', function()
    it('rejects an invalid option', function()
      assert.has_error(function()
        ---@diagnostic disable-next-line: assign-type-mismatch
        config.setup({ additional_extensions = 'php' })
      end)
    end)

    it('rejects an unknown rename_properties key', function()
      assert.has_error(function()
        config.setup({ rename_properties = { rename_everything = true } })
      end)
    end)

    it('is exposed by the main module', function()
      require('php-namespace-refactor').setup({ rename = false })

      assert.is_false(config.get().rename)
    end)
  end)

  describe('validate', function()
    it('accepts a partial config', function()
      assert.is_true(config.validate({ rename = false }))
    end)

    it('accepts rename_properties as a table', function()
      assert.is_true(config.validate({ rename_properties = { rename_mismatched_names = false } }))
    end)

    it('returns the error of an invalid option', function()
      local ok, err = config.validate({ ignored_directories = { 1 } })

      assert.is_false(ok)
      assert.matches('ignored_directories', err)
    end)
  end)

  -- Port of src/test/PropertyRenameSettingsResolver.test.ts
  describe('property_rename_settings', function()
    ---@param value any
    local function resolve(value)
      return config.property_rename_settings(vim.tbl_extend('force', config.defaults, { rename_properties = value }))
    end

    it('resolves false to disabled', function()
      assert.are.same({ enabled = false, rename_mismatched_names = false }, resolve(false))
    end)

    it('resolves nil (unset) to disabled', function()
      assert.are.same({ enabled = false, rename_mismatched_names = false }, resolve(nil))
    end)

    it('resolves true to enabled, with the mismatch behavior also on by default', function()
      assert.are.same({ enabled = true, rename_mismatched_names = true }, resolve(true))
    end)

    it('resolves an empty table to enabled, with the mismatch behavior also on by default', function()
      assert.are.same({ enabled = true, rename_mismatched_names = true }, resolve({}))
    end)

    it('resolves { rename_mismatched_names = true } to enabled with the mismatch behavior on', function()
      assert.are.same({ enabled = true, rename_mismatched_names = true }, resolve({ rename_mismatched_names = true }))
    end)

    it('resolves { rename_mismatched_names = false } to enabled with the mismatch behavior off', function()
      assert.are.same({ enabled = true, rename_mismatched_names = false }, resolve({ rename_mismatched_names = false }))
    end)

    it('reads the resolved config when none is given', function()
      config.setup({ rename_properties = true })

      assert.are.same({ enabled = true, rename_mismatched_names = true }, config.property_rename_settings())
    end)
  end)
end)
