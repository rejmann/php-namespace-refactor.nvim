local assert = require('luassert')
local config = require('php-namespace-refactor.config')
local path = require('php-namespace-refactor.domain.path')

-- Port of src/test/FileExtensionResolver.test.ts
--
-- https://github.com/rejmann/php-namespace-refactor/issues/72
--
-- `additional_extensions` must be honoured when matching a file's extension,
-- with the longest configured suffix winning so a compound convention like
-- `class.php` is never shadowed by the plain `php` entry.
describe('path.match_extension', function()
  it('matches the default .php extension with no configuration', function()
    assert.are.equal('.php', path.match_extension('Color.php', {}))
  end)

  it('matches a configured compound extension in full', function()
    assert.are.equal('.class.php', path.match_extension('Color.class.php', { 'class.php' }))
  end)

  it('prefers the longest configured suffix over the plain extension', function()
    assert.are.equal('.enum.php', path.match_extension('Color.enum.php', { 'enum.php' }))
  end)

  it('still matches the plain extension when no compound suffix applies', function()
    assert.are.equal('.php', path.match_extension('Repository.php', { 'enum.php' }))
  end)

  it('matches case-insensitively but returns the suffix in its original case', function()
    assert.are.equal('.ENUM.PHP', path.match_extension('Color.ENUM.PHP', { 'enum.php' }))
  end)

  it('strips a leading dot from configured extensions', function()
    assert.are.equal('.class.php', path.match_extension('Color.class.php', { '.class.php' }))
  end)

  it('returns nil when nothing configured matches', function()
    assert.is_nil(path.match_extension('readme.txt', {}))
  end)

  it('always includes php even when additional_extensions omits it', function()
    assert.are.equal('.php', path.match_extension('Color.php', { 'trait.php' }))
  end)

  describe('without explicit extensions', function()
    after_each(function()
      config._reset()
    end)

    it('reads additional_extensions from the config', function()
      config.setup({ additional_extensions = { 'enum.php' } })

      assert.are.equal('.enum.php', path.match_extension('Color.enum.php'))
    end)
  end)
end)

describe('path.normalize_extensions', function()
  it('trims, lowercases, strips dots and deduplicates, keeping php first', function()
    assert.are.same(
      { 'php', 'class.php', 'inc' },
      path.normalize_extensions({ ' .Class.PHP ', 'PHP', '', '..inc', 'inc' })
    )
  end)
end)

-- Port of src/test/WorkspacePathResolver.test.ts
--
-- https://github.com/rejmann/php-namespace-refactor/issues/72
--
-- Compound file-naming conventions (Color.enum.php, Repository.trait.php, ...) must
-- only lose the segments listed in `additional_extensions`, never a chunk of the class
-- name itself.
describe('path', function()
  describe('class_name_from_path', function()
    it('strips a plain .php extension', function()
      assert.are.equal('Color', path.class_name_from_path('/src/Domain/Color.php', {}))
    end)

    it('honours configured compound extensions, keeping the middle segment out', function()
      local extensions = { 'class.php', 'trait.php', 'enum.php', 'interface.php' }

      assert.are.equal('Color', path.class_name_from_path('/src/Domain/Color.enum.php', extensions))
      assert.are.equal('Repository', path.class_name_from_path('/src/Domain/Repository.trait.php', extensions))
      assert.are.equal('Foo', path.class_name_from_path('/src/Domain/Foo.interface.php', extensions))
      assert.are.equal('Bar', path.class_name_from_path('/src/Domain/Bar.class.php', extensions))
    end)

    it('leaks the middle segment when the compound extension is not configured', function()
      -- Documents today's default behaviour: without `class.php` in
      -- additional_extensions there is no way to tell the middle segment
      -- apart from the class name, so it stays in the extracted name.
      assert.are.equal('OutroTest.class', path.class_name_from_path('/src/Domain/OutroTest.class.php', {}))
    end)

    it('matches configured extensions case-insensitively', function()
      assert.are.equal('Color', path.class_name_from_path('/src/Domain/Color.ENUM.php', { 'enum.php' }))
    end)

    it('picks the longest matching suffix so plain .php never shadows a compound extension', function()
      assert.are.equal('Color', path.class_name_from_path('/src/Domain/Color.enum.php', { 'enum.php' }))
    end)

    it('leaves the file name untouched when no configured extension matches', function()
      assert.are.equal('readme.txt', path.class_name_from_path('/src/Domain/readme.txt', {}))
    end)
  end)

  describe('extension_from_path', function()
    it('returns the plain .php extension', function()
      assert.are.equal('.php', path.extension_from_path('/src/Domain/Color.php', {}))
    end)

    it('returns the full compound extension when configured', function()
      assert.are.equal('.enum.php', path.extension_from_path('/src/Domain/Color.enum.php', { 'enum.php' }))
    end)

    it('falls back to the last dot segment when nothing configured matches', function()
      assert.are.equal('.txt', path.extension_from_path('/src/Domain/readme.txt', {}))
    end)

    it('returns an empty string for a dotfile or a name without a dot', function()
      assert.are.equal('', path.extension_from_path('/src/.htaccess', {}))
      assert.are.equal('', path.extension_from_path('/src/Makefile', {}))
    end)
  end)

  describe('directory_from_path', function()
    it('returns the containing directory', function()
      assert.are.equal('/src/Domain', path.directory_from_path('/src/Domain/Color.php'))
    end)
  end)

  describe('relative_path', function()
    it('strips the root and the separator', function()
      assert.are.equal('src/Domain/Color.php', path.relative_path('/app/src/Domain/Color.php', '/app'))
      assert.are.equal('src/Domain/Color.php', path.relative_path('/app/src/Domain/Color.php', '/app/'))
    end)

    it('leaves a path outside the root unchanged', function()
      assert.are.equal('/application/src/Color.php', path.relative_path('/application/src/Color.php', '/app'))
    end)
  end)
end)
