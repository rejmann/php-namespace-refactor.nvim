local assert = require('luassert')
local patterns = require('php-namespace-refactor.domain.php.patterns')

-- Port of src/test/PhpPatterns.test.ts
describe('patterns.class_declaration', function()
  -- Scenario 3 – when renaming a class by name, the current name must be
  -- found in the declaration for replacement.
  --
  -- Scenario 4 – when renaming the file, the declared class name must be
  -- detected so it can be updated along with its annotations and imports.
  describe('Scenario 3/4 – detect class declaration for renaming', function()
    it('captures a simple class name', function()
      assert.are.equal('UserService', patterns.class_declaration('class UserService {}'))
    end)

    it('captures an abstract class name', function()
      assert.are.equal('BaseRepository', patterns.class_declaration('abstract class BaseRepository {}'))
    end)

    it('captures a final class name', function()
      assert.are.equal('PaymentGateway', patterns.class_declaration('final class PaymentGateway {}'))
    end)

    it('captures an interface name', function()
      assert.are.equal('RepositoryInterface', patterns.class_declaration('interface RepositoryInterface {}'))
    end)

    it('captures a trait name', function()
      assert.are.equal('HasTimestamps', patterns.class_declaration('trait HasTimestamps {}'))
    end)

    it('captures an enum name', function()
      assert.are.equal('ClassEnum', patterns.class_declaration('enum ClassEnum {}'))
    end)

    it('captures a backed enum name', function()
      assert.are.equal('PaymentStatus', patterns.class_declaration('enum PaymentStatus: string {}'))
    end)

    it('captures the class name in a full PHP file with namespace and use', function()
      local content = table.concat({
        '<?php',
        '',
        'namespace App\\Domain;',
        '',
        'use App\\Contracts\\EntityInterface;',
        '',
        'class Order implements EntityInterface',
        '{',
        '}',
      }, '\n')

      assert.are.equal('Order', patterns.class_declaration(content))
    end)

    it('does not capture comments containing the word class before the real declaration', function()
      assert.are.equal('Real', patterns.class_declaration('// class Fake\nclass Real {}'))
    end)
  end)

  it('returns the byte range of the name', function()
    local content = '<?php\n\n  final class Foo_1 extends Bar {}'
    local name, s, e = patterns.class_declaration(content)

    assert.are.equal('Foo_1', name)
    assert.are.equal('Foo_1', content:sub(s --[[@as integer]], e --[[@as integer]]))
  end)

  it('returns nil without a declaration', function()
    assert.is_nil(patterns.class_declaration('<?php\n\n$class = new class {};\nfunction classes() {}'))
  end)

  it('does not take a keyword prefix as the keyword', function()
    assert.is_nil(patterns.class_declaration('classic Foo {}'))
  end)
end)

describe('patterns.find_all / replace_all (namespace boundary guard)', function()
  -- Bug – a class "RenamedClass" can coexist with a sibling namespace of
  -- the same name (e.g. a RenamedClass.php file next to a
  -- RenamedClass/ directory). Renaming the class to "RenamedClassTeste"
  -- must not corrupt aliased imports from that sibling namespace, such as
  -- "use ...\RenamedClass\Foo\FormType as FooFormType;",
  -- because "RenamedClass" there is a namespace segment, not the class.
  describe('Guard against matching an identifier that is a namespace-path prefix of a longer one', function()
    it('replaces the identifier when it stands alone as a full FQCN', function()
      local result = patterns.replace_all(
        'use App\\Controller\\Atendimento\\RenamedClass;',
        'App\\Controller\\Atendimento\\RenamedClass',
        'App\\Controller\\Atendimento\\RenamedClassTeste',
        { left_boundary = false }
      )

      assert.are.equal('use App\\Controller\\Atendimento\\RenamedClassTeste;', result)
    end)

    it('does not touch aliased imports from a deeper sub-namespace sharing the same prefix', function()
      local content = table.concat({
        'use App\\Controller\\Atendimento\\RenamedClass\\Foo\\FormType as FooFormType;',
        'use App\\Controller\\Atendimento\\RenamedClass\\Bar\\FormType as BarFormType;',
      }, '\n')

      local result = patterns.replace_all(content, 'RenamedClass', 'RenamedClassTeste')

      assert.are.equal(content, result)
    end)

    it('still replaces the bare identifier when it is not part of a namespace path', function()
      local result, count = patterns.replace_all(
        'private RenamedClass $instance;\n\nnew RenamedClass();',
        'RenamedClass',
        'RenamedClassTeste'
      )

      assert.are.equal('private RenamedClassTeste $instance;\n\nnew RenamedClassTeste();', result)
      assert.are.equal(2, count)
    end)

    it('does not match a suffix identifier that merely starts with the same characters', function()
      local content = 'use App\\Domain\\RenamedClassAbstract;'

      assert.are.equal(content, (patterns.replace_all(content, 'RenamedClass', 'RenamedClassTeste')))
    end)
  end)

  -- Bug – renaming "DetalhePagamentoDTO" to "DetalhePagamentoDTOAbstract" was
  -- corrupting an unrelated "use ...DetalhePagamentoDTOAbstract;" statement
  -- already present in the same file, turning it into
  -- "...DetalhePagamentoDTOAbstractAbstract" because the namespace replace
  -- regex matched the old FQCN as a mere prefix of the longer one.
  describe('Guard against matching a FQCN that is a prefix of a longer identifier', function()
    it('replaces the old namespace when it is not followed by extra identifier characters', function()
      local result = patterns.replace_all(
        'use SharedBundle\\DetalhePagamentoDTO;',
        'SharedBundle\\DetalhePagamentoDTO',
        'SharedBundle\\DetalhePagamentoDTOAbstract',
        { left_boundary = false }
      )

      assert.are.equal('use SharedBundle\\DetalhePagamentoDTOAbstract;', result)
    end)

    it('does not touch an unrelated FQCN that has the old namespace as a prefix', function()
      local content = table.concat({
        'use SharedBundle\\DetalhePagamentoDTO;',
        'use SharedBundle\\DetalhePagamentoDTOAbstract;',
      }, '\n')

      local result = patterns.replace_all(
        content,
        'SharedBundle\\DetalhePagamentoDTO',
        'SharedBundle\\DetalhePagamentoDTOAbstract',
        { left_boundary = false }
      )

      assert.are.equal(
        table.concat({
          'use SharedBundle\\DetalhePagamentoDTOAbstract;',
          'use SharedBundle\\DetalhePagamentoDTOAbstract;',
        }, '\n'),
        result
      )
    end)
  end)

  describe('left_boundary = false', function()
    it('matches a namespace inside a leading-backslash FQCN', function()
      local result = patterns.replace_all('new \\App\\Foo();', 'App\\Foo', 'App\\Bar', { left_boundary = false })

      assert.are.equal('new \\App\\Bar();', result)
    end)

    it('is required for that: the default guard skips it', function()
      assert.is_false(patterns.contains('new \\App\\Foo();', 'App\\Foo'))
    end)
  end)

  it('returns 1-based inclusive byte ranges', function()
    assert.are.same({ { 1, 3 }, { 9, 11 } }, patterns.find_all('Foo and Foo', 'Foo'))
  end)

  it('keeps scanning after a guarded occurrence', function()
    assert.are.same({ { 8, 10 } }, patterns.find_all('FooFoo Foo', 'Foo'))
  end)

  it('treats non-ASCII neighbors as boundaries, like the JS regex', function()
    assert.are.same({ { 3, 5 } }, patterns.find_all('éFoo', 'Foo'))
  end)

  it('finds nothing for an empty needle', function()
    assert.are.same({}, patterns.find_all('Foo', ''))
  end)

  it('treats regex-special characters literally', function()
    assert.is_true(patterns.contains('a.b (x)', '(x)'))
    assert.is_false(patterns.contains('axb', 'a.b'))
  end)
end)
