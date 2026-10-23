---@mod php-namespace-refactor PHP Namespace Refactor

local M = {}

---Optional: the plugin also reads its options from `vim.g.php_namespace_refactor`.
---@param opts? php_namespace_refactor.Opts
function M.setup(opts)
  require('php-namespace-refactor.config').setup(opts)
end

---@class php_namespace_refactor.Subcommand
---@field impl fun(args: string[], opts: table) Runs the subcommand with its arguments
---@field complete? fun(arg_lead: string): string[] Completes the subcommand's arguments

---Subcommands of :PhpNamespaceRefactor, registered as each feature lands.
---@type table<string, php_namespace_refactor.Subcommand>
M.subcommands = {
  move = {
    impl = function(args)
      require('php-namespace-refactor.app.move').command(args)
    end,
    complete = function(arg_lead)
      return require('php-namespace-refactor.app.move').complete(arg_lead)
    end,
  },
  rename = {
    impl = function()
      require('php-namespace-refactor.app.rename_feature').rename()
    end,
  },
}

---Moves a PHP file or a directory and refactors the project for it:
---namespaces, class names, references and imports.
---@param old string
---@param new string
---@param opts? php_namespace_refactor.MoveOpts
---@return boolean ok
---@return string? err
function M.move(old, new, opts)
  return require('php-namespace-refactor.app.move').move(old, new, opts)
end

---Renames the class or namespace declared on the cursor line, asking for
---the new name with vim.ui.input(). A class rename renames its file; a
---namespace rename moves the file to the namespace's PSR-4 directory.
---@param opts? php_namespace_refactor.MoveOpts
function M.rename(opts)
  require('php-namespace-refactor.app.rename_feature').rename(opts)
end

---Entry point of the :PhpNamespaceRefactor user command.
---@param opts table Options passed by nvim_create_user_command
function M.command(opts)
  local args = opts.fargs
  local name = args[1]
  local subcommand = M.subcommands[name]

  if not subcommand then
    vim.notify(('PhpNamespaceRefactor: unknown subcommand "%s"'):format(name), vim.log.levels.ERROR)
    return
  end

  subcommand.impl(vim.list_slice(args, 2), opts)
end

---Completion for the :PhpNamespaceRefactor user command.
---@param arg_lead string
---@param cmdline string
---@return string[]
function M.complete(arg_lead, cmdline)
  local name, sub_arg_lead = cmdline:match("^['<,'>]*PhpNamespaceRefactor[!]*%s+(%S+)%s+(.*)$")
  if name and sub_arg_lead and M.subcommands[name] and M.subcommands[name].complete then
    return M.subcommands[name].complete(sub_arg_lead)
  end

  if cmdline:match("^['<,'>]*PhpNamespaceRefactor[!]*%s+%w*$") then
    return vim
      .iter(vim.tbl_keys(M.subcommands))
      :filter(function(key)
        return key:find(arg_lead, 1, true) == 1
      end)
      :totable()
  end

  return {}
end

return M
