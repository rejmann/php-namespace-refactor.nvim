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

-- No default mappings, see :help php-namespace-refactor-mappings
vim.keymap.set('n', '<Plug>(PhpNamespaceRefactorRename)', function()
  require('php-namespace-refactor').rename()
end, { desc = 'Rename the PHP class or namespace under the cursor' })

local group = vim.api.nvim_create_augroup('PhpNamespaceRefactor', {})

-- Build the namespace index of a composer project the first time one of its
-- PHP files is opened, rather than at startup.
vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'php',
  desc = 'Build the PHP namespace index of the project',
  callback = function(args)
    local file = vim.api.nvim_buf_get_name(args.buf)
    if file ~= '' then
      require('php-namespace-refactor.infra.index').ensure_built(file)
    end
  end,
})

vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  desc = 'Update the PHP namespace index',
  callback = function(args)
    require('php-namespace-refactor.infra.index').on_write(vim.api.nvim_buf_get_name(args.buf))
  end,
})
