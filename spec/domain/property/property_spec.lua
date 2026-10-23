local assert = require('luassert')
local constructor_span = require('php-namespace-refactor.domain.property.constructor_span')
local declaration = require('php-namespace-refactor.domain.property.declaration')
local locator = require('php-namespace-refactor.domain.property.locator')

-- Port of src/test/ClassTypedPropertyLocator.test.ts
describe('property.locator.locate', function()
  it('finds a promoted property', function()
    local text = table.concat({
      'class UserController',
      '{',
      '  public function __construct(private Test $test)',
      '  {',
      '  }',
      '}',
    }, '\n')

    assert.are.same(
      { property_name = 'test', is_promoted = true, has_separate_declaration = false },
      locator.locate(text, 'Test')
    )
  end)

  it('finds a promoted readonly property regardless of modifier order', function()
    local first = locator.locate('function __construct(private readonly Test $test) {}', 'Test')
    local second = locator.locate('function __construct(readonly private Test $test) {}', 'Test')

    assert.are.equal('test', first and first.property_name)
    assert.are.equal('test', second and second.property_name)
  end)

  it('finds a non-promoted property confirmed by a constructor assignment', function()
    local text = table.concat({
      'class UserController',
      '{',
      '  private Test $test;',
      '',
      '  public function __construct(Test $test)',
      '  {',
      '    $this->test = $test;',
      '  }',
      '}',
    }, '\n')

    assert.are.same(
      { property_name = 'test', is_promoted = false, has_separate_declaration = true },
      locator.locate(text, 'Test')
    )
  end)

  it('finds an untyped property declared only via a @var docblock', function()
    local text = table.concat({
      'class UserService',
      '{',
      '  /**',
      '   * @var UserRepository',
      '   */',
      '  private $repository;',
      '',
      '  public function __construct(UserRepository $repository)',
      '  {',
      '    $this->repository = $repository;',
      '  }',
      '}',
    }, '\n')

    assert.are.same(
      { property_name = 'repository', is_promoted = false, has_separate_declaration = true },
      locator.locate(text, 'UserRepository')
    )
  end)

  it('ignores a non-promoted parameter that is never stored on $this', function()
    local text = table.concat({
      'class Validator',
      '{',
      '  public function __construct(Test $test)',
      '  {',
      '    $test->validate();',
      '  }',
      '}',
    }, '\n')

    assert.is_nil(locator.locate(text, 'Test'))
  end)

  it('matches a property with a mismatched name', function()
    local match = locator.locate('function __construct(private Test $service) {}', 'Test')

    assert.are.equal('service', match and match.property_name)
  end)

  it('matches a nullable type hint', function()
    local match = locator.locate('function __construct(private ?Test $test) {}', 'Test')

    assert.are.equal('test', match and match.property_name)
  end)

  it('returns nil when there is no constructor', function()
    assert.is_nil(locator.locate('class Test {}', 'Test'))
  end)

  it('returns nil when the class type does not appear in the constructor', function()
    assert.is_nil(locator.locate('function __construct(private Other $other) {}', 'Test'))
  end)

  it('returns nil when two parameters share the same type (ambiguous)', function()
    assert.is_nil(locator.locate('function __construct(private Test $a, private Test $b) {}', 'Test'))
  end)

  it('ignores attributes, defaults and other parameters', function()
    local text = table.concat({
      'function __construct(',
      '    #[Autowire(service: "a, b")] private Test $test,',
      '    private array $options = [1, 2],',
      '    private OtherTest $other,',
      ') {}',
    }, '\n')

    local match = locator.locate(text, 'Test')

    assert.are.equal('test', match and match.property_name)
  end)

  it('does not take a type that merely ends with the class name', function()
    assert.is_nil(locator.locate('function __construct(private MyTest $test) {}', 'Test'))
  end)

  it('matches a fully qualified type only when not promoted, as the TS regexes did', function()
    local match = locator.locate('function __construct(private \\App\\Test $test) {}', 'Test')

    assert.is_nil(match, 'promotion modifiers must directly precede the type, as in the TS regex')
    assert.are.equal(
      'test',
      (locator.locate('function __construct(\\App\\Test $test) { $this->test = $test; }', 'Test') or {}).property_name
    )
  end)
end)

describe('property.locator.property_name', function()
  it('lowercases the first letter', function()
    assert.are.equal('userRepository', locator.property_name('UserRepository'))
  end)
end)

describe('property.constructor_span.find', function()
  it('finds the parameter list and the body', function()
    local text = 'class A {\n  public function __construct(array $a = [], ?B $b = null) {\n    $x = fn() => 1;\n  }\n}'
    local span = assert(constructor_span.find(text))

    assert.are.equal('array $a = [], ?B $b = null', text:sub(span.params_start + 1, span.params_end))
    assert.are.equal('{\n    $x = fn() => 1;\n  }', text:sub(span.body_start + 1, span.body_end))
    assert.are.equal('function __construct', text:sub(span.constructor_start + 1, span.constructor_start + 20))
  end)

  it('handles a constructor without a body', function()
    local text = 'interface A { public function __construct(B $b); }'
    local span = assert(constructor_span.find(text))

    assert.are.equal('B $b', text:sub(span.params_start + 1, span.params_end))
    assert.are.equal(span.body_start, span.body_end)
  end)

  it('returns nil without a constructor or with unbalanced parentheses', function()
    assert.is_nil(constructor_span.find('class A {}'))
    assert.is_nil(constructor_span.find('function __construct(B $b'))
  end)
end)

describe('property.declaration.find', function()
  it('finds a typed declaration', function()
    local text = 'class A {\n  private readonly ?Test $test ;\n}'
    local s, e = declaration.find(text, 'Test', 'test')

    assert.are.equal('private readonly ?Test $test ;', text:sub(s + 1, e))
  end)

  it('finds an untyped declaration', function()
    local text = 'class A {\n  protected $test;\n}'
    local s, e = declaration.find(text, 'Test', 'test')

    assert.are.equal('protected $test;', text:sub(s + 1, e))
  end)

  it('returns the first declaration across visibilities', function()
    local text = 'public $other;\nprotected Test $test;\nprivate Test $test;'
    local s = declaration.find(text, 'Test', 'test')

    assert.are.equal(15, s)
  end)

  it('does not match another type, another variable or a method', function()
    assert.is_nil(declaration.find('private Other $test;', 'Test', 'test'))
    assert.is_nil(declaration.find('private Test $testing;', 'Test', 'test'))
    assert.is_nil(declaration.find('private function test() {}', 'Test', 'test'))
  end)
end)
