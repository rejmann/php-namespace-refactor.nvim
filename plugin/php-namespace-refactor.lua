if vim.g.loaded_php_namespace_refactor then
  return
end
vim.g.loaded_php_namespace_refactor = true

-- Keep this file small: modules are only required once a command actually runs.
-- See :help lua-plugin-lazy
vim.api.nvim_create_user_command('PhpNamespaceRefactor', function(opts)
  require('php-namespace-refactor').command(opts)
end, {
  nargs = '+',
  desc = 'PHP Namespace Refactor',
  complete = function(arg_lead, cmdline, _)
    return require('php-namespace-refactor').complete(arg_lead, cmdline)
  end,
})
