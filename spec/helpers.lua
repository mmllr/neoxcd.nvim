local assert = require("luassert")

---@class StubbedCommand
---@field output string
---@field code integer|integer[]
---@field use_on_stdout boolean
---@field error? string

return {
  ---Returns a cmd function that can be used to stub commands
  ---@param stubbed_commands table<string, StubbedCommand>
  ---@return fun(cmd: string[], on_stdout: fun(error: string?, data: string?)|nil, on_stderr: fun(error: string?, data: string?)|nil, on_exit: fun(obj: vim.SystemCompleted))
  setup_run_cmd = function(stubbed_commands)
    return function(cmd, on_stdout, on_stderr, on_exit)
      local key = table.concat(cmd, " ")
      assert.is.is_not_nil(stubbed_commands[key], "Expected to find\n" .. key .. "\nin stubbed commands")
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
      if stubbed_commands[key].error ~= nil then
        on_stderr(stubbed_commands[key].error, nil)
      end
      on_exit({
        signal = 0,
        stdout = stubbed_commands[key].use_on_stdout and nil or stubbed_commands[key].output,
        code = next_code(),
      })
      stubbed_commands[key] = nil
    end
  end,

  ---Stubs file reads
  ---@param files table<string, string>
  ---@return async fun(path: string): string?
  stub_file_read = function(files)
    return function(path)
      return files[path]
    end
  end,

  ---Stubs file writes
  ---@param files table<string, string>
  ---@return async fun(path: string, content: string): boolean
  stub_file_write = function(files)
    return function(path, content)
      files[path] = content
      return true
    end
  end,

  ---@param cmds table<string, StubbedCommand>
  ---@param code number|number[]
  ---@param stubbed_cmd string[]
  ---@param output string
  stub_external_cmd = function(cmds, code, stubbed_cmd, output)
    cmds[table.concat(stubbed_cmd, " ")] = { code = code, output = output, use_on_stdout = false }
  end,
}
