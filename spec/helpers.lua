---@class StubbedCommand
---@field output string
---@field code integer|integer[]
---@field use_on_stdout boolean

return {
  ---Returns a cmd function that can be used to stub commands
  ---@param stubbed_commands table<string, StubbedCommand>
  ---@return fun(cmd: string[], on_stdout: fun(error: string?, data: string?)|nil, on_exit: fun(obj: vim.SystemCompleted))
  setup_run_cmd = function(stubbed_commands)
    return function(cmd, on_stdout, on_exit)
      local key = table.concat(cmd, " ")
      if stubbed_commands[key].use_on_stdout then
        for line in string.gmatch(stubbed_commands[key].output, "[^\r\n]+") do
          on_stdout(nil, line)
        end
      end
      ---@return integer
      local function next_code()
        if type(stubbed_commands[key].code) == "number" then
          ---@diagnostic disable-next-line: return-type-mismatch
          return stubbed_commands[key].code
        elseif #stubbed_commands[key].code > 0 then
          local code = stubbed_commands[key].code[1]
          ---@diagnostic disable-next-line: param-type-mismatch
          table.remove(stubbed_commands[key].code, 1)
          return code
        else
          error("Command " .. key .. " has no more codes to return")
        end
      end
      on_exit({
        signal = 0,
        stdout = stubbed_commands[key].use_on_stdout and nil or stubbed_commands[key].output,
        code = next_code(),
      })
      stubbed_commands[key] = nil
    end
  end,
}
