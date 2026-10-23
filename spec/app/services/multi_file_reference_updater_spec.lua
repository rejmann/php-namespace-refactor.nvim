local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local files = require('php-namespace-refactor.infra.files')
local fs = require('php-namespace-refactor.infra.fs')
local index_module = require('php-namespace-refactor.infra.index')
local namespace_batch_updater = require('php-namespace-refactor.app.services.namespace_batch_updater')
local updater = require('php-namespace-refactor.app.services.multi_file_reference_updater')

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

---Index of `root` with the given files already parsed.
---@param root string
---@param indexed string[] Relative paths
---@return php_namespace_refactor.Index
local function index_with(root, indexed)
  local index = index_module.new(root, vim.fn.tempname() .. '/index.json')
  for _, relative in ipairs(indexed) do
    index:parse_and_add(root .. '/' .. relative, fs.read_file(root .. '/' .. relative) --[[@as string]])
  end
  return index
end

---@param file string
---@return string
local function read(file)
  return fs.read_text(file) --[[@as string]]
end

---@param text string
---@param needle string
local function assert_contains(text, needle)
  assert.is_truthy(text:find(needle, 1, true), ('expected %q in:\n%s'):format(needle, text))
end

---@param text string
---@param needle string
local function count(text, needle)
  local n = 0
  local init = 1
  while true do
    local s = text:find(needle, init, true)
    if not s then
      return n
    end
    n = n + 1
    init = s + 1
  end
end

local order_controller =
  '<?php\n\nnamespace App\\Http;\n\nuse App\\Domain\\Order;\n\nclass OrderController\n{\n    private Order $order;\n}\n'

-- Port of src/test/MultiFileReferenceUpdater.test.ts
describe('multi_file_reference_updater', function()
  before_each(function()
    files.clear_cache()
    config._reset()
  end)

  after_each(function()
    config._reset()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) ~= '' then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  -- https://github.com/rejmann/php-namespace-refactor/issues/72 (item 4)
  --
  -- Multi-file reference updates used to write straight to disk, bypassing
  -- the undo stack entirely. With edit_files_in_background off, files are
  -- loaded into buffers and the change can be undone there.
  it('with edit_files_in_background off, updates references through an undoable buffer change', function()
    local root = project({
      ['src/NewDomain/Order.php'] = '<?php\n\nnamespace App\\NewDomain;\n\nclass Order\n{\n}\n',
      ['src/Http/OrderController.php'] = order_controller,
    })
    local consumer = root .. '/src/Http/OrderController.php'
    config.setup({ edit_files_in_background = false })

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\NewDomain\\Order',
      old_path = root .. '/src/NewDomain/Order.php',
      new_path = root .. '/src/NewDomain/Order.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    local bufnr = assert(fs.find_buffer(consumer))
    assert_contains(fs.buffer_text(bufnr), 'use App\\NewDomain\\Order;')
    assert.is_true(vim.bo[bufnr].modified)
    assert.are.equal(order_controller, fs.read_file(consumer))

    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('silent undo')
    end)
    assert.are.equal(order_controller, fs.buffer_text(bufnr))
  end)

  -- https://github.com/rejmann/php-namespace-refactor/issues/73
  --
  -- With edit_files_in_background on (the default), files that weren't
  -- already open get their edit saved straight through instead of sitting
  -- in an unsaved buffer.
  it('with edit_files_in_background on, saves edits to files that were not already open', function()
    local root = project({
      ['src/NewDomain/Order.php'] = '<?php\n\nnamespace App\\NewDomain;\n\nclass Order\n{\n}\n',
      ['src/Http/OrderController.php'] = order_controller,
    })
    local consumer = root .. '/src/Http/OrderController.php'

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\NewDomain\\Order',
      old_path = root .. '/src/NewDomain/Order.php',
      new_path = root .. '/src/NewDomain/Order.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    assert.is_nil(fs.find_buffer(consumer))
    assert_contains(fs.read_file(consumer) --[[@as string]], 'use App\\NewDomain\\Order;')
  end)

  it('with edit_files_in_background on, leaves already-open files as an unsaved change', function()
    local root = project({
      ['src/NewDomain/Order.php'] = '<?php\n\nnamespace App\\NewDomain;\n\nclass Order\n{\n}\n',
      ['src/Http/OrderController.php'] = order_controller,
    })
    local consumer = root .. '/src/Http/OrderController.php'
    local bufnr = vim.fn.bufadd(consumer)
    vim.fn.bufload(bufnr)

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\NewDomain\\Order',
      old_path = root .. '/src/NewDomain/Order.php',
      new_path = root .. '/src/NewDomain/Order.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    assert_contains(fs.buffer_text(bufnr), 'use App\\NewDomain\\Order;')
    assert.is_true(vim.bo[bufnr].modified)
    assert.are.equal(order_controller, fs.read_file(consumer))
  end)

  it('renaming the class itself does not double-replace the class name inside its own FQCN', function()
    -- The bare class name (e.g. "Order") is always a substring of its own
    -- FQCN match (e.g. "App\Domain\Order"), so combining both replacements
    -- into one edit risks overlapping ranges for the same file.
    local root = project({ ['src/Http/OrderController.php'] = order_controller })
    local consumer = root .. '/src/Http/OrderController.php'

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\Domain\\PurchaseOrder',
      old_path = root .. '/src/Domain/Order.php',
      new_path = root .. '/src/Domain/PurchaseOrder.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    local text = read(consumer)
    assert_contains(text, 'use App\\Domain\\PurchaseOrder;')
    assert_contains(text, 'private PurchaseOrder $order;')
    assert.are.equal(1, count(text, 'use App\\Domain\\PurchaseOrder;'))
    assert.is_nil(text:find('private Order $order', 1, true))
  end)

  it('with property renaming enabled, renames the constructor property in the same pass as the class rename', function()
    local root = project({
      ['src/Http/OrderController.php'] = '<?php\n\nnamespace App\\Http;\n\nuse App\\Domain\\Order;\n\nclass OrderController\n{\n    public function __construct(private Order $order)\n    {\n    }\n\n    public function run(): void\n    {\n        $this->order->run();\n    }\n}\n',
    })
    local consumer = root .. '/src/Http/OrderController.php'
    config.setup({ rename_properties = { rename_mismatched_names = false } })

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\Domain\\PurchaseOrder',
      old_path = root .. '/src/Domain/Order.php',
      new_path = root .. '/src/Domain/PurchaseOrder.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    local text = read(consumer)
    assert_contains(text, 'private PurchaseOrder $purchaseOrder')
    assert_contains(text, '$this->purchaseOrder->run();')
    assert.is_nil(text:find('$order', 1, true))
  end)

  it('with property renaming enabled, renames a non-promoted property in the same pass as the class rename', function()
    local root = project({
      ['src/Http/OrderController.php'] = '<?php\n\nnamespace App\\Http;\n\nuse App\\Domain\\Order;\n\nclass OrderController\n{\n    private Order $order;\n\n    public function __construct(Order $order)\n    {\n        $this->order = $order;\n    }\n}\n',
    })
    local consumer = root .. '/src/Http/OrderController.php'
    config.setup({ rename_properties = { rename_mismatched_names = false } })

    updater.execute({
      old_namespace = 'App\\Domain\\Order',
      new_namespace = 'App\\Domain\\PurchaseOrder',
      old_path = root .. '/src/Domain/Order.php',
      new_path = root .. '/src/Domain/PurchaseOrder.php',
      index = index_with(root, { 'src/Http/OrderController.php' }),
    })

    local text = read(consumer)
    assert_contains(text, 'private PurchaseOrder $purchaseOrder;')
    assert_contains(text, '__construct(PurchaseOrder $purchaseOrder)')
    assert_contains(text, '$this->purchaseOrder = $purchaseOrder;')
    assert.is_nil(text:find('$order', 1, true))
  end)

  it(
    'with rename_mismatched_names off, still renames the class name and import when the property is left alone',
    function()
      -- "$service" doesn't follow the old class-name convention ("order"), so
      -- the property itself must stay untouched - but that must not stop the
      -- class name and import from being renamed everywhere else in the file.
      local root = project({
        ['src/Http/OrderController.php'] = '<?php\n\nnamespace App\\Http;\n\nuse App\\Domain\\Order;\n\nclass OrderController\n{\n    public function __construct(private Order $service)\n    {\n    }\n}\n',
      })
      local consumer = root .. '/src/Http/OrderController.php'
      config.setup({ rename_properties = { rename_mismatched_names = false } })

      updater.execute({
        old_namespace = 'App\\Domain\\Order',
        new_namespace = 'App\\Domain\\PurchaseOrder',
        old_path = root .. '/src/Domain/Order.php',
        new_path = root .. '/src/Domain/PurchaseOrder.php',
        index = index_with(root, { 'src/Http/OrderController.php' }),
      })

      local text = read(consumer)
      assert_contains(text, 'use App\\Domain\\PurchaseOrder;')
      assert_contains(text, 'private PurchaseOrder $service')
    end
  )

  -- A class can share its name with a sibling namespace (e.g. a
  -- RenamedClass.php file next to a RenamedClass/ directory holding
  -- Foo/FormType.php and Bar/FormType.php). Renaming the class to
  -- RenamedClassTest must not corrupt aliased imports that merely start
  -- with the old FQCN but actually point into that sibling namespace.
  it('renaming a class does not corrupt aliased imports from a sub-namespace sharing its name', function()
    local root = project({
      ['src/Controller/RenamedClassController.php'] = table.concat({
        '<?php',
        '',
        'namespace App\\Controller;',
        '',
        'use App\\Controller\\RenamedClass;',
        'use App\\Controller\\RenamedClass\\Foo\\FormType as FooFormType;',
        'use App\\Controller\\RenamedClass\\Bar\\FormType as BarFormType;',
        '',
        'class RenamedClassController',
        '{',
        '    private RenamedClass $instance;',
        '}',
        '',
      }, '\n'),
    })
    local consumer = root .. '/src/Controller/RenamedClassController.php'
    -- The consumer shares the class's namespace, so the import remover would
    -- drop the (redundant) renamed import; the TS suite stubbed it out too.
    config.setup({ remove_unused_imports = false })

    updater.execute({
      old_namespace = 'App\\Controller\\RenamedClass',
      new_namespace = 'App\\Controller\\RenamedClassTest',
      old_path = root .. '/src/Controller/RenamedClass.php',
      new_path = root .. '/src/Controller/RenamedClassTest.php',
      index = index_with(root, { 'src/Controller/RenamedClassController.php' }),
    })

    local text = read(consumer)
    assert_contains(text, 'use App\\Controller\\RenamedClassTest;')
    assert_contains(text, 'private RenamedClassTest $instance;')
    assert_contains(text, 'use App\\Controller\\RenamedClass\\Foo\\FormType as FooFormType;')
    assert_contains(text, 'use App\\Controller\\RenamedClass\\Bar\\FormType as BarFormType;')
  end)

  describe('beyond the TS suite', function()
    it('finds references by scanning when the index does not know them', function()
      local root = project({ ['src/Http/OrderController.php'] = order_controller })

      local affected = updater.execute({
        old_namespace = 'App\\Domain\\Order',
        new_namespace = 'App\\Sales\\Order',
        old_path = root .. '/src/Domain/Order.php',
        new_path = root .. '/src/Sales/Order.php',
        index = index_with(root, {}),
      })

      assert.are.same({ root .. '/src/Http/OrderController.php' }, affected)
      assert_contains(read(root .. '/src/Http/OrderController.php'), 'use App\\Sales\\Order;')
    end)

    it('updates fully qualified references with a leading backslash', function()
      local root = project({
        ['src/Http/Factory.php'] = '<?php\n\nnamespace App\\Http;\n\nclass Factory\n{\n    public function make() { return new \\App\\Domain\\Order(); }\n}\n',
      })

      updater.execute({
        old_namespace = 'App\\Domain\\Order',
        new_namespace = 'App\\Sales\\Order',
        old_path = root .. '/src/Domain/Order.php',
        new_path = root .. '/src/Sales/Order.php',
        index = index_with(root, {}),
      })

      assert_contains(read(root .. '/src/Http/Factory.php'), 'new \\App\\Sales\\Order();')
    end)

    it('imports the class in files left behind in its old directory', function()
      local root = project({
        ['src/Domain/Invoice.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Invoice\n{\n    private Order $order;\n}\n',
        ['src/Domain/Customer.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Customer\n{\n}\n',
      })

      local affected = updater.execute({
        old_namespace = 'App\\Domain\\Order',
        new_namespace = 'App\\Sales\\Order',
        old_path = root .. '/src/Domain/Order.php',
        new_path = root .. '/src/Sales/Order.php',
        index = index_with(root, {}),
      })

      table.sort(affected)
      assert.are.same({ root .. '/src/Domain/Customer.php', root .. '/src/Domain/Invoice.php' }, affected)
      assert.are.equal(
        '<?php\n\nnamespace App\\Domain;\n\nuse App\\Sales\\Order;\n\nclass Invoice\n{\n    private Order $order;\n}\n',
        read(root .. '/src/Domain/Invoice.php')
      )
      assert.are.equal(
        '<?php\n\nnamespace App\\Domain;\n\nclass Customer\n{\n}\n',
        read(root .. '/src/Domain/Customer.php')
      )
    end)

    it('renames the short name in sibling files when the class is renamed in place', function()
      local root = project({
        ['src/Domain/Invoice.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Invoice\n{\n    private Order $order;\n}\n',
      })

      updater.execute({
        old_namespace = 'App\\Domain\\Order',
        new_namespace = 'App\\Domain\\PurchaseOrder',
        old_path = root .. '/src/Domain/Order.php',
        new_path = root .. '/src/Domain/PurchaseOrder.php',
        index = index_with(root, {}),
      })

      assert.are.equal(
        '<?php\n\nnamespace App\\Domain;\n\nclass Invoice\n{\n    private PurchaseOrder $order;\n}\n',
        read(root .. '/src/Domain/Invoice.php')
      )
    end)

    it('returns nothing outside a composer project', function()
      assert.are.same(
        {},
        updater.execute({
          old_namespace = 'A\\B',
          new_namespace = 'A\\C',
          old_path = '/nonexistent/B.php',
          new_path = '/nonexistent/C.php',
        })
      )
    end)
  end)
end)

describe('namespace_batch_updater', function()
  local cache_dir

  before_each(function()
    files.clear_cache()
    index_module._reset()
    cache_dir = require('luassert.stub')(index_module, 'cache_dir').returns(vim.fn.tempname())
  end)

  after_each(function()
    cache_dir:revert()
  end)

  it('updates the moved file and its references', function()
    local root = project({
      ['src/Sales/Order.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order\n{\n}\n',
      ['src/Http/OrderController.php'] = order_controller,
    })

    local affected = namespace_batch_updater.execute(root .. '/src/Domain/Order.php', root .. '/src/Sales/Order.php')

    assert.are.same({ root .. '/src/Http/OrderController.php' }, affected)
    assert.are.equal('<?php\n\nnamespace App\\Sales;\n\nclass Order\n{\n}\n', read(root .. '/src/Sales/Order.php'))
    assert_contains(read(root .. '/src/Http/OrderController.php'), 'use App\\Sales\\Order;')
  end)

  it('renames the class of a renamed file', function()
    local root = project({
      ['src/Domain/PurchaseOrder.php'] = '<?php\n\nnamespace App\\Domain;\n\nclass Order\n{\n}\n',
      ['src/Http/OrderController.php'] = order_controller,
    })

    namespace_batch_updater.execute(root .. '/src/Domain/Order.php', root .. '/src/Domain/PurchaseOrder.php')

    assert.are.equal(
      '<?php\n\nnamespace App\\Domain;\n\nclass PurchaseOrder\n{\n}\n',
      read(root .. '/src/Domain/PurchaseOrder.php')
    )
    local text = read(root .. '/src/Http/OrderController.php')
    assert_contains(text, 'use App\\Domain\\PurchaseOrder;')
    assert_contains(text, 'private PurchaseOrder $order;')
  end)

  it('does nothing for a file outside every psr-4 mapping or without a namespace declaration', function()
    local root = project({
      ['bin/Tool.php'] = '<?php\n\nnamespace App;\n\nclass Tool {}\n',
      ['src/Helpers.php'] = '<?php\n\nfunction helper() {}\n',
    })

    assert.are.same({}, namespace_batch_updater.execute(root .. '/lib/Tool.php', root .. '/bin/Tool.php'))
    assert.are.same({}, namespace_batch_updater.execute(root .. '/src/Old/Helpers.php', root .. '/src/Helpers.php'))
  end)
end)
