local assert = require('luassert')
local class_name_updater = require('php-namespace-refactor.app.services.class_name_updater')
local config = require('php-namespace-refactor.config')
local fs = require('php-namespace-refactor.infra.fs')
local moved_file_namespace_updater = require('php-namespace-refactor.app.services.moved_file_namespace_updater')

---@param file_name string
---@param content string
---@return string path
local function temp_php_file(file_name, content)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local file = dir .. '/' .. file_name
  assert(fs.write_file(file, content))
  return file
end

---@param extensions string[]
local function configure(extensions)
  config.setup({ additional_extensions = extensions, edit_files_in_background = true })
end

-- Port of src/test/ClassNameUpdater.test.ts
--
-- https://github.com/rejmann/php-namespace-refactor/issues/72
--
-- Compound file names (Color.enum.php, Color.class.php, ...) must not corrupt the
-- declaration once the middle segment is honoured as part of the configured extension.
describe('class_name_updater', function()
  after_each(function()
    config._reset()
  end)

  it('does not corrupt "enum Color" in Color.enum.php when the extension is configured', function()
    local file = temp_php_file('Color.enum.php', '<?php\n\nenum Color\n{\n    case RED;\n    case BLUE;\n}\n')
    configure({ 'class.php', 'trait.php', 'enum.php', 'interface.php' })

    assert.is_false(class_name_updater.execute(file))

    local text = fs.read_file(file) --[[@as string]]
    assert.matches('enum Color\n', text, 1, true)
    assert.is_nil(text:find('Color.enum', 1, true), 'declaration got corrupted:\n' .. text)
  end)

  it('does not corrupt "class Color" in Color.class.php when the extension is configured', function()
    local file = temp_php_file('Color.class.php', '<?php\n\nclass Color\n{\n}\n')
    configure({ 'class.php', 'trait.php', 'enum.php', 'interface.php' })

    class_name_updater.execute(file)

    local text = fs.read_file(file) --[[@as string]]
    assert.matches('class Color\n', text, 1, true)
    assert.is_nil(text:find('Color.class', 1, true), 'declaration got corrupted:\n' .. text)
  end)

  it('renames a mismatched declaration to the file name without leaking the extension segment', function()
    local file = temp_php_file('Color.enum.php', '<?php\n\nenum Shade\n{\n    case RED;\n}\n')
    configure({ 'enum.php' })

    assert.is_true(class_name_updater.execute(file))

    assert.are.equal('<?php\n\nenum Color\n{\n    case RED;\n}\n', fs.read_file(file))
  end)

  it('reproduces the reported bug: without the compound extension configured, the declaration is corrupted', function()
    -- https://github.com/rejmann/php-namespace-refactor/issues/72 as originally reported:
    -- additional_extensions defaults to { 'php' }, so ".class" leaks into the class name.
    local file = temp_php_file('OutroTest.class.php', '<?php\n\nclass Outro\n{\n}\n')
    configure({})

    class_name_updater.execute(file)

    assert.matches('class OutroTest.class\n', fs.read_file(file), 1, true)
  end)

  -- A class can share its name with a sibling namespace (e.g. a
  -- RenamedClass.php file next to a RenamedClass/ directory holding
  -- Foo/Type.php). When RenamedClass.php is renamed to
  -- RenamedClassTest.php, its own aliased imports from that sibling
  -- namespace must not be corrupted just because they start with the old name.
  it('does not corrupt its own aliased imports from a sub-namespace sharing its name', function()
    local file = temp_php_file(
      'RenamedClassTest.php',
      table.concat({
        '<?php',
        '',
        'namespace App\\Controller;',
        '',
        'use App\\Controller\\RenamedClass\\Foo\\Type as FooType;',
        'use App\\Controller\\RenamedClass\\Bar\\Type as BarType;',
        '',
        'class RenamedClass',
        '{',
        '    public static function create(): RenamedClass {}',
        '}',
        '',
      }, '\n')
    )
    configure({})

    class_name_updater.execute(file)

    local text = fs.read_file(file) --[[@as string]]
    assert.matches('class RenamedClassTest\n', text, 1, true)
    assert.matches('create(): RenamedClassTest {}', text, 1, true)
    assert.matches('use App\\Controller\\RenamedClass\\Foo\\Type as FooType;', text, 1, true)
    assert.matches('use App\\Controller\\RenamedClass\\Bar\\Type as BarType;', text, 1, true)
  end)

  it('edits the loaded buffer instead of the file on disk', function()
    local file = temp_php_file('Color.php', '<?php\n\nclass Shade\n{\n}\n')
    configure({})
    local bufnr = vim.fn.bufadd(file)
    vim.fn.bufload(bufnr)

    class_name_updater.execute(file)

    assert.are.equal('class Color', vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1])
    assert.matches('class Shade', fs.read_file(file), 1, true)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('does nothing for a file without a declaration', function()
    local file = temp_php_file('helpers.php', '<?php\n\nfunction helper() {}\n')

    assert.is_false(class_name_updater.execute(file))
    assert.is_false(class_name_updater.execute('/nonexistent/Foo.php'))
  end)
end)

describe('moved_file_namespace_updater', function()
  describe('collect_edit', function()
    it('replaces only the namespace name', function()
      local text = '<?php\n\nnamespace App\\Old;\n\nclass Foo {}\n'
      local text_edit = assert(moved_file_namespace_updater.collect_edit(text, 'App\\New'))

      assert.are.equal('App\\Old', text:sub(text_edit.start + 1, text_edit.finish))
      assert.are.equal('App\\New', text_edit.text)
    end)

    it('handles an indented declaration', function()
      local text = '<?php\n  namespace App;\n'
      local text_edit = assert(moved_file_namespace_updater.collect_edit(text, 'Acme'))

      assert.are.equal('App', text:sub(text_edit.start + 1, text_edit.finish))
    end)

    it('returns nil without a namespace declaration', function()
      assert.is_nil(moved_file_namespace_updater.collect_edit('<?php\n\nclass Foo {}\n', 'App'))
    end)
  end)

  describe('execute', function()
    it('rewrites the namespace declaration, keeping the blank lines around it', function()
      local file = temp_php_file('Foo.php', '<?php\n\nnamespace App\\Old;\n\nclass Foo {}\n')

      assert.is_true(moved_file_namespace_updater.execute(file, 'App\\New'))

      assert.are.equal('<?php\n\nnamespace App\\New;\n\nclass Foo {}\n', fs.read_file(file))
    end)

    it('reports a file without a namespace declaration', function()
      local file = temp_php_file('Foo.php', '<?php\n\nclass Foo {}\n')

      assert.is_false(moved_file_namespace_updater.execute(file, 'App'))
      assert.is_false(moved_file_namespace_updater.execute('/nonexistent/Foo.php', 'App'))
    end)
  end)
end)
