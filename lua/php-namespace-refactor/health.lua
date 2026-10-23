---@mod php-namespace-refactor.health Health check
---
---`:checkhealth php-namespace-refactor`

local M = {}

local health = vim.health

local function check_neovim()
  if vim.fn.has('nvim-0.10') == 1 then
    health.ok(('Neovim %s'):format(tostring(vim.version())))
  else
    health.error('Neovim 0.10 or later is required')
  end
end

local function check_config()
  local config = require('php-namespace-refactor.config')
  local opts = config.user_opts()

  local ok, err = config.validate(opts)
  if ok then
    health.ok('configuration is valid')
  else
    health.error(('invalid configuration: %s'):format(err), 'The defaults are used until it is fixed')
  end

  local unknown = config.unknown_keys(opts)
  if #unknown > 0 then
    health.warn(
      ('unknown options: %s'):format(table.concat(unknown, ', ')),
      ('Known options: %s'):format(table.concat(vim.tbl_keys(config.defaults), ', '))
    )
  end
end

local function check_tools()
  for _, tool in ipairs({ 'rg', 'git' }) do
    if vim.fn.executable(tool) == 1 then
      health.ok(('`%s` found'):format(tool))
      return
    end
  end
  health.warn(
    'neither `rg` nor `git` found',
    'Project files are listed by walking the directory tree, which is slower and ignores .gitignore'
  )
end

---@return string? file
local function current_file()
  local name = vim.api.nvim_buf_get_name(0)
  -- :checkhealth opens its own buffer; look at the alternate one.
  if vim.bo.filetype == 'checkhealth' then
    local alternate = vim.fn.bufnr('#')
    name = alternate ~= -1 and vim.api.nvim_buf_get_name(alternate) or ''
  end
  return name ~= '' and name or nil
end

local function check_project()
  local composer = require('php-namespace-refactor.infra.composer')
  local file = current_file() or (vim.fn.getcwd() .. '/_')
  local root = composer.root(file)
  if not root then
    health.warn(
      ('no composer.json found above %s'):format(vim.fn.fnamemodify(file, ':h:~')),
      'Open a file of a composer project (the plugin only works inside one)'
    )
    return
  end
  health.info(('project: %s'):format(vim.fn.fnamemodify(root, ':~')))

  local entries = composer.read(root).entries
  if #entries == 0 then
    health.error(
      'composer.json has no psr-4 autoload mapping',
      'Add an "autoload": { "psr-4": { ... } } section, namespaces are derived from it'
    )
  else
    local mappings = vim.tbl_map(function(entry)
      local directory = entry.directory == '' and '.' or entry.directory
      return ('%s\\ → %s/%s'):format(entry.prefix, directory, entry.dev and ' (dev)' or '')
    end, entries)
    table.sort(mappings)
    health.ok(('psr-4: %s'):format(table.concat(mappings, ', ')))
  end

  local index = require('php-namespace-refactor.infra.index').get(root)
  if index.ready then
    health.ok(('namespace index: %d files'):format(index:count()))
  else
    health.info(('namespace index: %d files loaded, built when a PHP file is opened'):format(index:count()))
  end

  local lsp_name = require('php-namespace-refactor.infra.lsp').NAME
  local clients = vim.tbl_filter(function(client)
    return client.config.root_dir == root
  end, vim.lsp.get_clients({ name = lsp_name }))
  if #clients > 0 then
    health.ok('file explorer integration: in-process language server attached')
  else
    health.info('file explorer integration: the in-process language server starts when a PHP file is opened')
  end
end

function M.check()
  health.start('php-namespace-refactor')
  check_neovim()
  check_config()
  check_tools()

  health.start('php-namespace-refactor: project')
  check_project()
end

return M
