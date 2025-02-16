---@class NeoxcdSubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback, taking the lead of the subcommand's arguments

---@type table<string, NeoxcdSubcommand>
local subcommand_tbl = {
  scheme = {
    impl = function(args, opts)
      require("neoxcd").select_schemes()
    end,
    -- This subcommand has no completions
  },
  build = {
    impl = function(args, opts)
      require("neoxcd").build()
      -- Implementation
    end,
    -- complete = function(subcmd_arg_lead)
    --     -- Simplified example
    --     local install_args = {
    --         "neorg",
    --         "rest.nvim",
    --         "rustaceanvim",
    --     }
    --     return vim.iter(install_args)
    --         :filter(function(install_arg)
    --             -- If the user has typed `:Rocks install ne`,
    --             -- this will match 'neorg'
    --             return install_arg:find(subcmd_arg_lead) ~= nil
    --         end)
    --         :totable()
    -- end,
    -- ...
  },
  clean = {
    impl = function(args, opts)
      require("neoxcd").clean()
    end,
    -- This subcommand has no completions
  },
  destination = {
    impl = function(args, opts)
      require("neoxcd").select_destination()
    end,
    -- This subcommand has no completions
  },
  run = {
    impl = function(args, opts)
      require("neoxcd").run()
    end,
    -- This subcommand has no completions
  },
  xcode = {
    impl = function(args, opts)
      require("neoxcd").open_in_xcode()
    end,
  },
  debug = {
    impl = function(args, opts)
      require("neoxcd").debug()
    end,
  },
  stop = {
    impl = function(args, opts)
      require("neoxcd").stop()
    end,
  },
  scan = {
    impl = function(args, opts)
      require("neoxcd").scan()
    end,
  },
}

---@param opts table :h lua-guide-commands-create
local function neoxcd(opts)
  local fargs = opts.fargs
  local subcommand_key = fargs[1]
  -- Get the subcommand's arguments, if any
  local args = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}
  local subcommand = subcommand_tbl[subcommand_key]
  if not subcommand then
    vim.notify("Neoxcd: Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
    return
  end
  -- Invoke the subcommand
  subcommand.impl(args, opts)
end

vim.api.nvim_create_user_command("Neoxcd", neoxcd, {
  nargs = "+",
  desc = "Neoxcd: Neovim Xcode Development",
  complete = function(arg_lead, cmdline, _)
    -- Get the subcommand.
    local subcmd_key, subcmd_arg_lead = cmdline:match("^['<,'>]*Neoxcd[!]*%s(%S+)%s(.*)$")
    if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
      -- The subcommand has completions. Return them.
      return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
    end
    -- Check if cmdline is a subcommand
    if cmdline:match("^['<,'>]*Neoxcd[!]*%s+%w*$") then
      -- Filter subcommands that match
      local subcommand_keys = vim.tbl_keys(subcommand_tbl)
      return vim
        .iter(subcommand_keys)
        :filter(function(key)
          return key:find(arg_lead) ~= nil
        end)
        :totable()
    end
  end,
  bang = true, -- If you want to support ! modifiers
})
