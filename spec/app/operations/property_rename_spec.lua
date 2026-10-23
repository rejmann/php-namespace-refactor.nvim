local assert = require('luassert')
local fs = require('php-namespace-refactor.infra.fs')
local property_rename = require('php-namespace-refactor.app.operations.property_rename')

---@param dir string
---@param file_name string
---@param content string
---@return string path
local function write_temp_php_file(dir, file_name, content)
  local file = dir .. '/' .. file_name
  assert(fs.write_file(file, content))
  return file
end

---@return string
local function temp_dir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  return dir
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

-- Port of src/test/PropertyRenameOperation.test.ts
describe('property_rename.execute', function()
  it('renames a promoted property that matches the old class-name convention', function()
    local dir = temp_dir()
    local consumer = write_temp_php_file(
      dir,
      'UserController.php',
      '<?php\n\nclass UserController\n{\n    public function __construct(private NewTest $test)\n    {\n    }\n\n    public function run(): void\n    {\n        $this->test->run();\n    }\n}\n'
    )

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = { consumer },
      rename_mismatched_names = false,
    })

    local text = read(consumer)
    assert_contains(text, 'private NewTest $newTest')
    assert_contains(text, '$this->newTest->run();')
    assert.is_nil(text:find('$test', 1, true), 'expected no leftover old property name, got:\n' .. text)
  end)

  it('renames a non-promoted property confirmed by its constructor assignment', function()
    local dir = temp_dir()
    local consumer = write_temp_php_file(
      dir,
      'UserController.php',
      '<?php\n\nclass UserController\n{\n    private NewTest $test;\n\n    public function __construct(NewTest $test)\n    {\n        $this->test = $test;\n    }\n}\n'
    )

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = { consumer },
      rename_mismatched_names = false,
    })

    local text = read(consumer)
    assert_contains(text, 'private NewTest $newTest;')
    assert_contains(text, '__construct(NewTest $newTest)')
    assert_contains(text, '$this->newTest = $newTest;')
  end)

  it('renames an untyped property declared only via a @var docblock', function()
    local dir = temp_dir()
    local consumer = write_temp_php_file(
      dir,
      'UserService.php',
      '<?php\n\nclass UserService\n{\n    /**\n     * @var ClientRepository\n     */\n    private $repository;\n\n    public function __construct(ClientRepository $repository)\n    {\n        $this->repository = $repository;\n    }\n}\n'
    )

    property_rename.execute({
      old_path = dir .. '/UserRepository.php',
      new_path = dir .. '/ClientRepository.php',
      affected_files = { consumer },
      rename_mismatched_names = true,
    })

    local text = read(consumer)
    assert_contains(text, 'private $clientRepository;')
    assert_contains(text, '__construct(ClientRepository $clientRepository)')
    assert_contains(text, '$this->clientRepository = $clientRepository;')
    assert.is_nil(text:find('$repository', 1, true), 'expected no leftover old property name, got:\n' .. text)
  end)

  it('leaves a mismatched property name untouched when rename_mismatched_names is false', function()
    local dir = temp_dir()
    local content =
      '<?php\n\nclass UserController\n{\n    public function __construct(private NewTest $service)\n    {\n    }\n}\n'
    local consumer = write_temp_php_file(dir, 'UserController.php', content)

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = { consumer },
      rename_mismatched_names = false,
    })

    assert.are.equal(content, read(consumer))
  end)

  it('renames a mismatched property name when rename_mismatched_names is true', function()
    local dir = temp_dir()
    local consumer = write_temp_php_file(
      dir,
      'UserController.php',
      '<?php\n\nclass UserController\n{\n    public function __construct(private NewTest $service)\n    {\n        $this->service->run();\n    }\n}\n'
    )

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = { consumer },
      rename_mismatched_names = true,
    })

    local text = read(consumer)
    assert_contains(text, 'private NewTest $newTest')
    assert_contains(text, '$this->newTest->run();')
  end)

  it('skips a file when two properties share the renamed class type (ambiguous)', function()
    local dir = temp_dir()
    local content =
      '<?php\n\nclass UserController\n{\n    public function __construct(private NewTest $a, private NewTest $b)\n    {\n    }\n}\n'
    local consumer = write_temp_php_file(dir, 'UserController.php', content)

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = { consumer },
      rename_mismatched_names = true,
    })

    assert.are.equal(content, read(consumer))
  end)

  it('does nothing when the class name did not actually change', function()
    local dir = temp_dir()
    local content =
      '<?php\n\nclass UserController\n{\n    public function __construct(private Test $test)\n    {\n    }\n}\n'
    local consumer = write_temp_php_file(dir, 'UserController.php', content)

    local result = property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/Test.php',
      affected_files = { consumer },
      rename_mismatched_names = false,
    })

    assert.is_nil(result)
    assert.are.equal(content, read(consumer))
  end)

  -- A file that textually contains the new class name but wasn't part of
  -- this rename's affected-files set (e.g. an unrelated class with the same
  -- short name in a different namespace) must never be touched - property
  -- renaming is scoped to exactly what the multi-file reference updater
  -- determined was affected by this rename, never a broader workspace scan.
  it('ignores a file that matches by text but was not part of the affected-files set', function()
    local dir = temp_dir()
    local content =
      '<?php\n\nnamespace Other;\n\nclass UnrelatedController\n{\n    public function __construct(private NewTest $test)\n    {\n    }\n}\n'
    local unrelated = write_temp_php_file(dir, 'UnrelatedController.php', content)

    property_rename.execute({
      old_path = dir .. '/Test.php',
      new_path = dir .. '/NewTest.php',
      affected_files = {},
      rename_mismatched_names = false,
    })

    assert.are.equal(content, read(unrelated))
  end)
end)

describe('property_rename.collect_edits', function()
  local names = assert(property_rename.resolve_names('/src/Test.php', '/src/NewTest.php'))

  it('still finds the property under the old class name, before the class rename is applied', function()
    local text =
      'class A {\n  public function __construct(private Test $test) {}\n  function b() { return $this->test; }\n}'

    local edits = property_rename.collect_edits(text, names, false)

    assert.are.equal(2, #edits)
    for _, text_edit in ipairs(edits) do
      assert.matches('newTest$', text_edit.text)
    end
  end)

  it('does not rename a longer property sharing the prefix', function()
    local text =
      'class A {\n  public function __construct(private Test $test) {}\n  function b() { return $this->testing; }\n}'

    local edits = property_rename.collect_edits(text, names, false)

    assert.are.equal(1, #edits)
    assert.are.equal('$newTest', edits[1].text)
  end)

  it('leaves a property already named after the new class alone', function()
    local text = 'class A { public function __construct(private NewTest $newTest) {} }'

    assert.are.same({}, property_rename.collect_edits(text, names, true))
  end)
end)

describe('property_rename.resolve_names', function()
  it('resolves the property names of both classes', function()
    assert.are.same({
      old_class_name = 'Test',
      new_class_name = 'NewTest',
      expected_old_name = 'test',
      expected_new_name = 'newTest',
    }, property_rename.resolve_names('/src/Test.php', '/src/NewTest.php'))
  end)

  it('returns nil when the class name is unchanged', function()
    assert.is_nil(property_rename.resolve_names('/src/Test.php', '/other/Test.php'))
  end)
end)
