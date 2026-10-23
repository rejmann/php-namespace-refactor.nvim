local assert = require('luassert')
local use_statement = require('php-namespace-refactor.domain.php.use_statement')

---0-based, end-exclusive offset right after `needle` in `text`.
---@param text string
---@param needle string
---@return integer
local function end_of(text, needle)
  local s = assert(text:find(needle, 1, true))
  return s - 1 + #needle
end

---@param text string
---@param edit? php_namespace_refactor.TextEdit
---@return string
local function apply(text, edit)
  if not edit then
    return text
  end
  return text:sub(1, edit.start) .. edit.text .. text:sub(edit.finish + 1)
end

-- Port of src/test/UseStatementLocator.test.ts
describe('use_statement.locate', function()
  -- Scenario 5/6 – find the correct insertion point for adding or removing
  -- use statements after moving a class between directories.
  describe('Scenario 5 – insertion point for a new use statement', function()
    it('returns position after the last existing use statement with is_first_use = false', function()
      local last_use = 'use App\\Domain\\Order;'
      local content = table.concat({
        '<?php',
        'namespace App\\Http;',
        '',
        'use App\\Domain\\User;',
        last_use,
        '',
        'class Controller {}',
      }, '\n')

      assert.are.same({ index = end_of(content, last_use), is_first_use = false }, use_statement.locate(content))
    end)

    it('returns position after namespace when there are no use statements with is_first_use = true', function()
      local ns_line = 'namespace App\\Http;'
      local content = table.concat({ '<?php', ns_line, '', 'class Controller {}' }, '\n')

      assert.are.same({ index = end_of(content, ns_line), is_first_use = true }, use_statement.locate(content))
    end)

    it('returns index 0 when there is no namespace or use statements', function()
      assert.are.equal(0, use_statement.locate('<?php\nclass Foo {}').index)
    end)
  end)

  describe('Additional cases', function()
    it('uses position after an aliased use statement as the insertion point', function()
      local use_line = 'use App\\Domain\\User as UserEntity;'
      local content = 'namespace App;\n' .. use_line .. '\nclass Foo {}'

      assert.are.same({ index = end_of(content, use_line), is_first_use = false }, use_statement.locate(content))
    end)

    it('file with only a namespace declaration returns is_first_use = true with index > 0', function()
      local location = use_statement.locate('<?php\nnamespace App\\Services;')

      assert.is_true(location.is_first_use)
      assert.is_true(location.index > 0)
    end)
  end)

  it('ignores indented use statements (traits inside a class)', function()
    local ns_line = 'namespace App;'
    local content = '<?php\n' .. ns_line .. '\n\nclass Foo\n{\n    use HasTimestamps;\n}\n'

    assert.are.same({ index = end_of(content, ns_line), is_first_use = true }, use_statement.locate(content))
  end)
end)

describe('use_statement.statement', function()
  it('builds a use statement preceded by a newline', function()
    assert.are.equal('\nuse App\\Domain\\User;', use_statement.statement('App\\Domain\\User'))
  end)

  it('rejects an empty namespace', function()
    assert.has_error(function()
      use_statement.statement('')
    end)
  end)

  it('concatenates several statements', function()
    assert.are.equal('\nuse App\\A;\nuse App\\B;', use_statement.statements({ 'App\\A', 'App\\B' }))
  end)
end)

-- Port of src/test/UseStatementInjector.test.ts
--
-- Reported bug: a sibling file that already imports a class kept getting the
-- same `use` statement appended again every time an unrelated file in the
-- same directory got renamed/moved, producing several identical duplicate
-- import lines over time.
describe('use_statement.inject', function()
  local consumer = '<?php\n\nnamespace App\\User;\n\nclass Consumer\n{\n}\n'

  it('does not append a duplicate use statement across repeated calls', function()
    local text = consumer

    for _ = 1, 4 do
      text = apply(text, use_statement.inject(text, use_statement.locate(text), '\nuse App\\User\\UserRepository;'))
    end

    local _, occurrences = text:gsub('use App\\User\\UserRepository;', '')
    assert.are.equal(1, occurrences, 'expected exactly one import, got:\n' .. text)
  end)

  it('still appends the import the first time it is missing', function()
    local text = apply(
      consumer,
      use_statement.inject(consumer, use_statement.locate(consumer), '\nuse App\\User\\UserRepository;')
    )

    assert.are.equal('<?php\n\nnamespace App\\User;\n\nuse App\\User\\UserRepository;\n\nclass Consumer\n{\n}\n', text)
  end)

  it('appends after the last use statement without extra blank lines', function()
    local text = '<?php\n\nnamespace App;\n\nuse App\\A;\n\nclass Foo {}\n'

    assert.are.equal(
      '<?php\n\nnamespace App;\n\nuse App\\A;\nuse App\\B;\n\nclass Foo {}\n',
      apply(text, use_statement.inject(text, use_statement.locate(text), '\nuse App\\B;'))
    )
  end)

  it('only adds the statements that are missing', function()
    local text = '<?php\n\nnamespace App;\n\nuse App\\A;\n'

    local edit = use_statement.inject(text, use_statement.locate(text), '\nuse App\\A;\nuse App\\B;\nuse App\\B;')

    assert.are.same({ start = #text - 1, finish = #text - 1, text = '\nuse App\\B;' }, edit)
  end)

  it('returns nil when everything is already imported', function()
    local text = '<?php\n\nnamespace App;\n\nuse App\\A;\n'

    assert.is_nil(use_statement.inject(text, use_statement.locate(text), '\nuse App\\A;'))
  end)
end)
