local assert = require('luassert')
local edit = require('php-namespace-refactor.infra.edit')
local fs = require('php-namespace-refactor.infra.fs')

---@param content string
---@return string path
local function temp_file(content)
  local path = vim.fn.tempname() .. '.php'
  assert(fs.write_file(path, content))
  return path
end

---@param path string
---@return integer bufnr
local function load_buffer(path)
  local bufnr = vim.fn.bufadd(path)
  vim.fn.bufload(bufnr)
  return bufnr
end

describe('fs', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) ~= '' then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  it('reads a file from disk when no buffer shows it', function()
    assert.are.equal('<?php\n', fs.read_text(temp_file('<?php\n')))
  end)

  it('prefers the unsaved contents of a loaded buffer', function()
    local path = temp_file('<?php\n')
    local bufnr = load_buffer(path)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'class Foo {}' })

    assert.are.equal('<?php\nclass Foo {}\n', fs.read_text(path))
  end)

  it('omits the trailing newline of a buffer without eol and fixeol', function()
    local path = temp_file('<?php')
    vim.bo[load_buffer(path)].fixeol = false

    assert.are.equal('<?php', fs.read_text(path))
  end)

  it('returns an error for a missing file', function()
    local text, err = fs.read_text('/nonexistent/Foo.php')

    assert.is_nil(text)
    assert.is_string(err)
  end)
end)

describe('edit', function()
  after_each(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(bufnr) ~= '' then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  describe('apply_to_text', function()
    it('applies edits regardless of the order they were added in', function()
      local text = edit.apply_to_text('use A; use B;', {
        { start = 11, finish = 12, text = 'Bar' },
        { start = 4, finish = 5, text = 'Foo' },
      })

      assert.are.equal('use Foo; use Bar;', text)
    end)

    it('keeps insertions at the same offset in the order they were added', function()
      local text = edit.apply_to_text('ab', {
        { start = 1, finish = 1, text = '1' },
        { start = 1, finish = 1, text = '2' },
      })

      assert.are.equal('a12b', text)
    end)

    it('rejects overlapping edits', function()
      local text, err = edit.apply_to_text('abcdef', {
        { start = 0, finish = 3, text = 'x' },
        { start = 2, finish = 4, text = 'y' },
      })

      assert.is_nil(text)
      assert.matches('overlapping', err)
    end)

    it('rejects an edit past the end of the text', function()
      assert.is_nil(edit.apply_to_text('abc', { { start = 2, finish = 4, text = '' } }))
    end)
  end)

  describe('WorkspaceEdit', function()
    it('collects edits per file in the order files were first edited', function()
      local workspace_edit = edit.new()
      workspace_edit:insert('/b.php', 0, 'x')
      workspace_edit:replace('/a.php', 0, 1, 'y')
      workspace_edit:insert('/b.php', 1, 'z')

      assert.are.same({ '/b.php', '/a.php' }, workspace_edit:paths())
      assert.are.equal(2, #workspace_edit:edits('/b.php'))
      assert.is_false(workspace_edit:is_empty())
      assert.is_true(edit.new():is_empty())
    end)

    it('writes files that are not loaded straight to disk', function()
      local path = temp_file('<?php\n\nnamespace App;\n')
      local workspace_edit = edit.new()
      workspace_edit:replace(path, 17, 20, 'Acme')

      local result = workspace_edit:apply({ background = true })

      assert.are.same({ changed = { path }, errors = {} }, result)
      assert.are.equal('<?php\n\nnamespace Acme;\n', fs.read_file(path))
      assert.is_nil(fs.find_buffer(path))
    end)

    it('edits a loaded buffer in place as a single undo step, leaving the file untouched', function()
      local path = temp_file('<?php\n\nnamespace App;\n\nclass Foo {}\n')
      local bufnr = load_buffer(path)
      local workspace_edit = edit.new()
      workspace_edit:replace(path, 17, 20, 'Acme')
      workspace_edit:insert(path, 21, '\nuse App\\Bar;')
      workspace_edit:replace(path, 29, 32, 'Baz')

      workspace_edit:apply({ background = true })

      assert.are.same(
        { '<?php', '', 'namespace Acme;', 'use App\\Bar;', '', 'class Baz {}' },
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      )
      assert.is_true(vim.bo[bufnr].modified)
      assert.are.equal('<?php\n\nnamespace App;\n\nclass Foo {}\n', fs.read_file(path))

      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd('silent undo')
      end)
      assert.are.same(
        { '<?php', '', 'namespace App;', '', 'class Foo {}' },
        vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      )
    end)

    it('handles an insertion after the final newline of a buffer', function()
      local path = temp_file('<?php\n')
      local bufnr = load_buffer(path)
      local workspace_edit = edit.new()
      workspace_edit:insert(path, 6, 'class Foo {}\n')

      workspace_edit:apply({ background = true })

      assert.are.same({ '<?php', 'class Foo {}' }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      assert.are.equal('<?php\nclass Foo {}\n', fs.buffer_text(bufnr))
    end)

    it('loads files into listed, unsaved buffers when not editing in background', function()
      local path = temp_file('<?php\n\nnamespace App;\n')
      local workspace_edit = edit.new()
      workspace_edit:replace(path, 17, 20, 'Acme')

      workspace_edit:apply({ background = false })

      local bufnr = assert(fs.find_buffer(path))
      assert.is_true(vim.bo[bufnr].buflisted)
      assert.is_true(vim.bo[bufnr].modified)
      assert.are.equal('<?php\n\nnamespace Acme;\n', fs.buffer_text(bufnr))
      assert.are.equal('<?php\n\nnamespace App;\n', fs.read_file(path))
    end)

    it('reports files it could not edit and keeps going', function()
      local path = temp_file('abc')
      local workspace_edit = edit.new()
      workspace_edit:insert('/nonexistent/Foo.php', 0, 'x')
      workspace_edit:replace(path, 0, 1, 'A')
      workspace_edit:replace(path, 0, 2, 'B')
      local other = temp_file('abc')
      workspace_edit:replace(other, 0, 1, 'A')

      local result = workspace_edit:apply({ background = true })

      assert.are.same({ other }, result.changed)
      assert.is_string(result.errors['/nonexistent/Foo.php'])
      assert.matches('overlapping', result.errors[path])
      assert.are.equal('abc', fs.read_file(path))
    end)

    it('does not count a file whose text ends up unchanged', function()
      local path = temp_file('abc')
      local workspace_edit = edit.new()
      workspace_edit:replace(path, 0, 1, 'a')

      assert.are.same({}, workspace_edit:apply({ background = true }).changed)
    end)
  end)
end)
