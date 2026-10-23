-- Minimal config for trying the plugin by hand:
--   nvim --clean -u spec/minimal_init.lua spec/fixtures/project/src/Foo/Bar.php
-- Work on a copy of spec/fixtures/project, the commands change files on disk.
local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.cmd('filetype plugin indent on')
vim.cmd('runtime plugin/php-namespace-refactor.lua')
