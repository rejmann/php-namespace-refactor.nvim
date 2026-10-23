---@mod php-namespace-refactor PHP Namespace Refactor

local M = {}

---@class php_namespace_refactor.Subcommand
---@field impl fun(args: string[], opts: table) Runs the subcommand with its arguments
---@field complete? fun(arg_lead: string): string[] Completes the subcommand's arguments

---Subcommands of :PhpNamespaceRefactor, registered as each feature lands.
---@type table<string, php_namespace_refactor.Subcommand>
M.subcommands = {}

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
