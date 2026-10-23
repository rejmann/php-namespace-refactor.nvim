local assert = require('luassert')
local unused_imports = require('php-namespace-refactor.domain.php.unused_imports')

-- Port of src/test/UnusedImportDetector.test.ts
describe('unused_imports.detect', function()
  -- Scenario 5 – when moving a class to a directory where it is used by other
  -- classes, those classes must receive the import automatically.
  -- detect() decides which class names are in use and not yet imported.
  describe('Scenario 5 – detect classes that need to be imported', function()
    it('returns the class name when it is used in the content and not yet imported', function()
      local content = 'namespace App\\Http;\n\nclass Controller {\n  public function index(UserService $s) {}\n}'

      assert.are.same({ 'UserService' }, unused_imports.detect(content, { 'UserService' }))
    end)

    it('returns multiple classes that are used and not imported', function()
      local content = 'namespace App;\n\nclass Foo {\n  public function run(UserService $u, OrderService $o) {}\n}'

      assert.are.same(
        { 'UserService', 'OrderService' },
        unused_imports.detect(content, { 'UserService', 'OrderService', 'PaymentService' })
      )
    end)

    it('does not return classes already imported via use statement', function()
      local content =
        'namespace App;\nuse App\\Domain\\UserService;\n\nclass Foo {\n  public function run(UserService $u) {}\n}'

      assert.are.same({}, unused_imports.detect(content, { 'UserService' }))
    end)
  end)

  -- Scenario 2 – when moving to the same directory where the class is already
  -- used, no import should be added. The detector must not return a class that
  -- already has a use statement.
  --
  -- Scenario 6 – when a class moves to a directory where another class already
  -- uses it and both end up in the same directory, the use statement should be
  -- removed. The detector must not flag the class as "needs import".
  describe('Scenario 2/6 – no duplicate import when use statement already exists', function()
    it('excludes a class with a fully-qualified use statement', function()
      local content = 'namespace App;\nuse App\\Services\\Order;\n\nclass Checkout {\n  function pay(Order $o) {}\n}'

      assert.are.same({}, unused_imports.detect(content, { 'Order' }))
    end)

    it('does not return a class that does not appear in the body even without a use statement', function()
      local content = table.concat({
        'namespace App;',
        'use App\\Domain\\User;',
        'use App\\Domain\\Product;',
        'class Cart { function add(User $u, Product $p) {} }',
      }, '\n')

      assert.are.same({}, unused_imports.detect(content, { 'User', 'Product', 'Order' }))
    end)

    it('returns only classes without a use statement when they appear in the body', function()
      local content = table.concat({
        'namespace App;',
        'use App\\Domain\\User;',
        'use App\\Domain\\Product;',
        'class Cart { function add(User $u, Product $p, Order $o) {} }',
      }, '\n')

      assert.are.same({ 'Order' }, unused_imports.detect(content, { 'User', 'Product', 'Order' }))
    end)
  end)

  describe('Additional cases', function()
    it('returns empty when none of the listed classes are used', function()
      local content = 'namespace App;\n\nclass Foo { function bar() { return 1; } }'

      assert.are.same({}, unused_imports.detect(content, { 'UserService', 'OrderService' }))
    end)

    it('returns empty when the class list is empty', function()
      assert.are.same({}, unused_imports.detect('class Foo {}', {}))
    end)

    it('does not duplicate results when a class appears multiple times in the content', function()
      local content = 'class Foo { function a(UserService $u) {} function b(UserService $u) {} }'

      assert.are.same({ 'UserService' }, unused_imports.detect(content, { 'UserService', 'UserService' }))
    end)

    -- A class can share its name with a sibling namespace (e.g. a
    -- RenamedClass.php file next to a RenamedClass/ directory). An
    -- aliased import from that sibling namespace, such as
    -- "use ...\RenamedClass\Foo\FormType as FooFormType;",
    -- must not make "RenamedClass" look used — it's a namespace segment
    -- there, not a reference to the class.
    it('does not treat a class name as used merely because it prefixes a sub-namespace path', function()
      local content = table.concat({
        'namespace App\\Controller;',
        'use App\\Controller\\RenamedClass\\Foo\\FormType as FooFormType;',
        'use App\\Controller\\RenamedClass\\Bar\\FormType as BarFormType;',
        'class Foo { function bar(FooFormType $f) {} }',
      }, '\n')

      assert.are.same({}, unused_imports.detect(content, { 'RenamedClass' }))
    end)

    it('does not take a word ending in "use" for a use statement', function()
      local content = 'class Foo {\n  // because Order is handy\n  function a(Order $o) {}\n}'

      assert.are.same({ 'Order' }, unused_imports.detect(content, { 'Order' }))
    end)
  end)
end)
