describe('php-namespace-refactor', function()
  it('loads the main module', function()
    local plugin = require('php-namespace-refactor')

    assert.is_table(plugin)
    assert.is_function(plugin.command)
    assert.is_function(plugin.complete)
  end)

  it('registers the :PhpNamespaceRefactor command', function()
    vim.g.loaded_php_namespace_refactor = nil
    dofile('plugin/php-namespace-refactor.lua')

    assert.is_not_nil(vim.api.nvim_get_commands({})['PhpNamespaceRefactor'])
  end)
end)
