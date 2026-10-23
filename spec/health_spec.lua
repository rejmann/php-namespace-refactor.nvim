local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local stub = require('luassert.stub')

---Runs the health check and returns what it reported, by level.
---@return table<string, string[]>
local function check()
  local reports = { start = {}, ok = {}, info = {}, warn = {}, error = {} }
  local stubs = {}
  for level in pairs(reports) do
    stubs[level] = stub(vim.health, level).invokes(function(msg)
      table.insert(reports[level], msg)
    end)
  end

  local ok, err = pcall(require('php-namespace-refactor.health').check)
  for _, s in pairs(stubs) do
    s:revert()
  end
  assert(ok, err)
  return reports
end

---@param messages string[]
---@param needle string
local function assert_reported(messages, needle)
  for _, msg in ipairs(messages) do
    if msg:find(needle, 1, true) then
      return
    end
  end
  error(('%q not reported in:\n%s'):format(needle, vim.inspect(messages)))
end

---@param composer_json string
---@return string root
local function project(composer_json)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. '/src', 'p')
  root = vim.uv.fs_realpath(root) --[[@as string]]
  assert(fs.write_file(root .. '/composer.json', composer_json))
  assert(fs.write_file(root .. '/src/Foo.php', '<?php\n\nnamespace App;\n\nclass Foo {}\n'))
  return root
end

describe(':checkhealth php-namespace-refactor', function()
  local cache_dir

  before_each(function()
    config._reset()
    vim.g.php_namespace_refactor = nil
    index_module._reset()
    cache_dir = stub(index_module, 'cache_dir').returns(vim.fn.tempname())
  end)

  after_each(function()
    cache_dir:revert()
    config._reset()
    vim.g.php_namespace_refactor = nil
    vim.cmd('silent! %bwipeout!')
  end)

  it('reports the Neovim version and a valid configuration', function()
    local reports = check()

    assert_reported(reports.start, 'php-namespace-refactor')
    assert_reported(reports.ok, 'Neovim ')
    assert_reported(reports.ok, 'configuration is valid')
  end)

  it('reports an invalid configuration and unknown options', function()
    vim.g.php_namespace_refactor = { rename = 'yes', renme = true }

    local reports = check()

    assert_reported(reports.error, 'invalid configuration: rename')
    assert_reported(reports.warn, 'unknown options: renme')
  end)

  it('reports the psr-4 mappings of the current project', function()
    local root = project('{"autoload": {"psr-4": {"App\\\\": "src/"}}, "autoload-dev": {"psr-4": {"Tests\\\\": ""}}}')
    vim.cmd.edit(root .. '/src/Foo.php')

    local reports = check()

    assert_reported(reports.info, 'project: ')
    assert_reported(reports.ok, 'App\\ → src/')
    assert_reported(reports.ok, 'Tests\\ → ./ (dev)')
    assert_reported(reports.info, 'namespace index')
  end)

  it('reports a composer.json without psr-4 mappings', function()
    local root = project('{"name": "acme/app"}')
    vim.cmd.edit(root .. '/src/Foo.php')

    assert_reported(check().error, 'no psr-4 autoload mapping')
  end)

  it('warns outside a composer project', function()
    vim.cmd.edit(vim.fn.tempname() .. '/Foo.php')

    assert_reported(check().warn, 'no composer.json found')
  end)

  it('reports the in-process language server once attached', function()
    local root = project('{"autoload": {"psr-4": {"App\\\\": "src/"}}}')
    vim.cmd.edit(root .. '/src/Foo.php')
    local client_id = require('php-namespace-refactor.infra.lsp').start(0)
    assert.is_true(vim.wait(5000, function()
      local client = vim.lsp.get_client_by_id(client_id --[[@as integer]])
      return client ~= nil and client.initialized == true
    end))

    assert_reported(check().ok, 'in-process language server attached')

    local client = vim.lsp.get_client_by_id(client_id --[[@as integer]])
    if client then
      if vim.fn.has('nvim-0.11') == 1 then
        client:stop(true)
      else
        ---@diagnostic disable-next-line: deprecated
        vim.lsp.stop_client(client.id, true)
      end
    end
  end)
end)
