local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local fs = require('php-namespace-refactor.infra.fs')
local import_remover = require('php-namespace-refactor.app.services.import_remover')
local missing_class_importer = require('php-namespace-refactor.app.services.missing_class_importer')

---Creates a composer project (`App\` → `src/`) with the given files.
---@param contents table<string, string> Relative path → content
---@return string root
local function project(contents)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  root = vim.uv.fs_realpath(root) --[[@as string]]
  assert(fs.write_file(root .. '/composer.json', '{"autoload": {"psr-4": {"App\\\\": "src/"}}}'))
  for relative, content in pairs(contents) do
    local file = root .. '/' .. relative
    vim.fn.mkdir(vim.fs.dirname(file), 'p')
    assert(fs.write_file(file, content))
  end
  return root
end

---@param file string
---@return string
local function read(file)
  return fs.read_file(file) --[[@as string]]
end

describe('import_remover', function()
  after_each(function()
    config._reset()
  end)

  it('removes the imports between the moved class and its new siblings', function()
    local root = project({
      ['src/Sales/Order.php'] = '<?php\n\nnamespace App\\Sales;\n\nuse App\\Sales\\Invoice;\nuse App\\Domain\\Customer;\n\nclass Order\n{\n}\n',
      ['src/Sales/Invoice.php'] = '<?php\n\nnamespace App\\Sales;\n\nuse App\\Sales\\Order;\n\nclass Invoice\n{\n}\n',
    })

    import_remover.execute(root .. '/src/Sales/Order.php')

    assert.are.equal(
      '<?php\n\nnamespace App\\Sales;\n\nuse App\\Domain\\Customer;\n\nclass Order\n{\n}\n',
      read(root .. '/src/Sales/Order.php')
    )
    assert.are.equal(
      '<?php\n\nnamespace App\\Sales;\n\n\nclass Invoice\n{\n}\n',
      read(root .. '/src/Sales/Invoice.php')
    )
  end)

  it('keeps an import of a same-named class from another namespace', function()
    local content = '<?php\n\nnamespace App\\Sales;\n\nuse App\\Legacy\\Invoice;\n\nclass Order\n{\n}\n'
    local root = project({
      ['src/Sales/Order.php'] = content,
      ['src/Sales/Invoice.php'] = '<?php\n\nnamespace App\\Sales;\n\nclass Invoice {}\n',
    })

    import_remover.execute(root .. '/src/Sales/Order.php')

    assert.are.equal(content, read(root .. '/src/Sales/Order.php'))
  end)

  it('keeps aliased imports, which code refers to by their alias', function()
    local content = '<?php\n\nnamespace App\\Sales;\n\nuse App\\Sales\\Invoice as Bill;\n\nclass Order\n{\n}\n'
    local root = project({
      ['src/Sales/Order.php'] = content,
      ['src/Sales/Invoice.php'] = '<?php\n\nnamespace App\\Sales;\n\nclass Invoice {}\n',
    })

    import_remover.execute(root .. '/src/Sales/Order.php')

    assert.are.equal(content, read(root .. '/src/Sales/Order.php'))
  end)

  it('does nothing when remove_unused_imports is off', function()
    local content = '<?php\n\nnamespace App\\Sales;\n\nuse App\\Sales\\Invoice;\n\nclass Order\n{\n}\n'
    local root = project({
      ['src/Sales/Order.php'] = content,
      ['src/Sales/Invoice.php'] = '<?php\n\nnamespace App\\Sales;\n\nclass Invoice {}\n',
    })
    config.setup({ remove_unused_imports = false })

    import_remover.execute(root .. '/src/Sales/Order.php')

    assert.are.equal(content, read(root .. '/src/Sales/Order.php'))
  end)

  describe('collect_edits', function()
    it('deletes a last line without a trailing newline', function()
      local text = 'namespace App;\nuse App\\Foo;'

      assert.are.same(
        { { start = 15, finish = 27, text = '' } },
        import_remover.collect_edits(text, 'App', { Foo = true })
      )
    end)
  end)
end)

describe('missing_class_importer', function()
  it('imports the old siblings the moved class used by short name', function()
    local root = project({
      ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer {}\n',
      ['src/Domain/Address.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Address {}\n',
      ['src/Domain/Unused.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Unused {}\n',
      ['src/Sales/Order.php'] = '<?php\n\nnamespace App\\Sales;\n\nclass Order\n{\n    public function __construct(private Customer $customer, private Address $address) {}\n}\n',
    })

    assert.is_true(missing_class_importer.execute(root .. '/src/Domain/Order.php', root .. '/src/Sales/Order.php'))

    assert.are.equal(
      '<?php\n\nnamespace App\\Sales;\n\nuse App\\Domain\\Address;\nuse App\\Domain\\Customer;\n\nclass Order\n{\n    public function __construct(private Customer $customer, private Address $address) {}\n}\n',
      read(root .. '/src/Sales/Order.php')
    )
  end)

  it('does nothing when the class stayed in the same directory', function()
    local root = project({
      ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer {}\n',
      ['src/Domain/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order { private Customer $c; }\n',
    })

    assert.is_false(missing_class_importer.execute(root .. '/src/Domain/Old.php', root .. '/src/Domain/Order.php'))
  end)

  it('does not import a class already imported, or the moved class itself', function()
    local content =
      '<?php\n\nnamespace App\\Sales;\n\nuse App\\Domain\\Customer;\n\nclass Order\n{\n    private Customer $c;\n    private ?Order $parent;\n}\n'
    local root = project({
      ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer {}\n',
      ['src/Domain/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order {}\n',
      ['src/Sales/Order.php'] = content,
    })

    assert.is_false(missing_class_importer.execute(root .. '/src/Domain/Order.php', root .. '/src/Sales/Order.php'))
    assert.are.equal(content, read(root .. '/src/Sales/Order.php'))
  end)

  it('does nothing when the old directory is gone', function()
    local root = project({ ['src/Sales/Order.php'] = '<?php\n\nnamespace App\\Sales;\n\nclass Order {}\n' })

    assert.is_false(missing_class_importer.execute(root .. '/src/Gone/Order.php', root .. '/src/Sales/Order.php'))
  end)
end)
