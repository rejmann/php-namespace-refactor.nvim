local assert = require('luassert')
local rename = require('php-namespace-refactor.domain.rename')

---@param content string
---@param line integer 0-based, like vscode.Position
---@return string
local function line_of(content, line)
  return vim.split(content, '\n')[line + 1]
end

-- Port of src/test/RenameTypeDetector.test.ts
describe('rename.detect_type', function()
  -- Scenario 3 – when renaming a class by name: detect that the cursor is on
  -- the class declaration to trigger the class rename.
  --
  -- Scenario 4 – when renaming the namespace: detect that the cursor is on
  -- the namespace declaration to trigger the namespace rename.
  describe('Scenario 3/4 – detect rename type (namespace vs class)', function()
    it('identifies a namespace line', function()
      assert.are.equal('namespace', rename.detect_type(line_of('<?php\nnamespace App\\Domain;\nclass Order {}', 1)))
    end)

    it('identifies a class line', function()
      assert.are.equal('class', rename.detect_type(line_of('<?php\nnamespace App\\Domain;\nclass Order {}', 2)))
    end)

    it('identifies an abstract class line', function()
      assert.are.equal('class', rename.detect_type(line_of('<?php\nnamespace App;\nabstract class BaseService {}', 2)))
    end)

    it('identifies an interface line', function()
      assert.are.equal('class', rename.detect_type(line_of('<?php\nnamespace App;\ninterface PaymentInterface {}', 2)))
    end)

    it('identifies a trait line', function()
      assert.are.equal('class', rename.detect_type(line_of('<?php\nnamespace App;\ntrait HasTimestamps {}', 2)))
    end)

    it('returns nil when the cursor is on an unidentifiable line', function()
      assert.is_nil(rename.detect_type(line_of('<?php\n// some comment\nclass Foo {}', 1)))
    end)
  end)

  it('identifies an enum line, which the TS detector rejected', function()
    assert.are.equal('class', rename.detect_type('enum Status: string'))
  end)
end)

describe('rename.extract_name', function()
  it('extracts the namespace', function()
    assert.are.equal('App\\Domain', rename.extract_name('namespace App\\Domain;'))
  end)

  it('extracts the class name', function()
    assert.are.equal('Order', rename.extract_name('final class Order extends Base'))
  end)

  it('returns nil for other lines', function()
    assert.is_nil(rename.extract_name('    public function order() {}'))
  end)
end)

describe('rename.validate', function()
  it('rejects an empty name', function()
    assert.are.equal('Name cannot be empty', rename.validate('  ', 'class'))
    assert.are.equal('Name cannot be empty', rename.validate('', 'namespace'))
  end)

  describe('class names', function()
    it('accepts a valid name', function()
      assert.is_nil(rename.validate('PurchaseOrder_2', 'class'))
      assert.is_nil(rename.validate('_Internal', 'class'))
    end)

    it('rejects invalid names with a specific message', function()
      assert.are.equal('Class name cannot start with a number', rename.validate('2Order', 'class'))
      assert.are.equal('Class name cannot contain hyphens (-)', rename.validate('Purchase-Order', 'class'))
      assert.are.equal('Class name cannot contain spaces', rename.validate('Purchase Order', 'class'))
      assert.matches('letter or underscore', rename.validate('Order!', 'class'))
      assert.matches('letter or underscore', rename.validate('App\\Order', 'class'))
    end)
  end)

  describe('namespaces', function()
    it('accepts a valid namespace', function()
      assert.is_nil(rename.validate('App\\Domain\\Sales_2', 'namespace'))
      assert.is_nil(rename.validate('App', 'namespace'))
    end)

    it('rejects invalid namespaces with a specific message', function()
      assert.are.equal('Cannot start with \\', rename.validate('\\App', 'namespace'))
      assert.are.equal('Cannot end with \\', rename.validate('App\\', 'namespace'))
      assert.are.equal('Cannot contain double \\\\', rename.validate('App\\\\Domain', 'namespace'))
      assert.are.equal('Must start with a letter', rename.validate('_App', 'namespace'))
      assert.are.equal('Invalid format. Use: Foo\\Bar', rename.validate('App\\2Domain', 'namespace'))
      assert.are.equal('Invalid format. Use: Foo\\Bar', rename.validate('App\\Do-main', 'namespace'))
    end)
  end)
end)
