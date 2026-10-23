-- Loaded by busted before any spec file (see .busted).
--
-- Busted insulates each spec file, unloading the modules it required when the
-- file ends. Neovim's runtime modules must not be unloaded that way: vim.lsp,
-- once loaded, keeps using its own vim.lsp.client, so a fresh copy required by
-- a later file would hold a separate client registry. Load them up front so
-- they stay shared.
require('vim.lsp')
require('vim.lsp.client')
