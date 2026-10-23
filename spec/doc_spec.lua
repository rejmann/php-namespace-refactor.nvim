local assert = require('luassert')

local DOC = 'doc/php-namespace-refactor.txt'

---Tags defined in a help tags file.
---@param tags_file string
---@return table<string, true>
local function read_tags(tags_file)
  local tags = {}
  for _, line in ipairs(vim.fn.readfile(tags_file)) do
    tags[line:match('^[^\t]+')] = true
  end
  return tags
end

describe('vimdoc', function()
  local lines = vim.fn.readfile(DOC)

  it('generates help tags without errors', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(lines, dir .. '/php-namespace-refactor.txt')

    assert.has_no.errors(function()
      vim.cmd.helptags(vim.fn.fnameescape(dir))
    end)
    assert.is_true(read_tags(dir .. '/tags')['php-namespace-refactor.txt'])
  end)

  it('only links to existing tags', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(lines, dir .. '/php-namespace-refactor.txt')
    vim.cmd.helptags(vim.fn.fnameescape(dir))
    local own = read_tags(dir .. '/tags')
    local runtime = read_tags(vim.env.VIMRUNTIME .. '/doc/tags')

    local missing = {}
    for _, line in ipairs(lines) do
      -- Skip code blocks, where | is plain text.
      if not line:match('^%s%s%s%s') then
        for tag in line:gmatch('|([^|%s]+)|') do
          if not own[tag] and not runtime[tag] then
            table.insert(missing, tag)
          end
        end
      end
    end

    assert.are.same({}, missing)
  end)

  it('keeps lines within 78 columns', function()
    local long = {}
    for i, line in ipairs(lines) do
      if vim.fn.strdisplaywidth(line) > 78 then
        table.insert(long, i)
      end
    end

    assert.are.same({}, long)
  end)
end)
