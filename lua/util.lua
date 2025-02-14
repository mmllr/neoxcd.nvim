local nio = require("nio")

---@class UtilOpts
---@field run_cmd? fun(cmd: string[], on_stdout: fun(error: string?, data: string?)|nil, on_exit: fun(obj: vim.SystemCompleted))
---@field run_dap? fun(config: dap.Configuration)

local M = {
  ---@type UtilOpts
  options = {},
}

---@class ExternalCommand
---@dfield execute fun(cmd: string[], on_exit: fun(code: number), on_stdout: fun(error: string, data: string))

---Find files with a specific extension in a directory
---@param extension string
---@param directory string
---@return string[]
function M.find_files_with_extension(extension, directory)
  local pattern = directory .. "/*." .. extension
  local files = nio.fn.glob(pattern, false, true) -- Get a list of files
  return files
end

---Helper for executing external commands
---@param cmd string[]
---@param on_stdout fun(error: string?, data: string?)|nil
---@param on_exit fun(obj: vim.SystemCompleted)
function M.run_job(cmd, on_stdout, on_exit)
  if M.options.run_cmd ~= nil and type(M.options.run_cmd) == "function" then
    M.options.run_cmd(cmd, on_stdout, on_exit)
    return
  end
  vim.system(cmd, {
    text = true,
    stdout = on_stdout or true,
  }, on_exit)
end

---@type fun(config: dap.Configuration)
M.run_dap = function(config)
  if M.options.run_dap and type(M.options.run_dap) == "function" then
    M.options.run_dap(config)
    return
  end
  local success, dap = pcall(require, "dap")

  if not success then
    error("neoxcd.nvim: Could not load nvim-dap plugin")
    return
  end

  dap.run(config)
end

---Concatenate two tables
---@param lhs table
---@param rhs table
---@return table
function M.concat(lhs, rhs)
  local result = {}
  for _, v in ipairs(lhs) do
    table.insert(result, v)
  end
  for _, v in ipairs(rhs) do
    table.insert(result, v)
  end
  return result
end

---Removes nil values from a table
---@param array any[]
---@return any[]
function M.lst_remove_nil_values(array)
  if #array == 0 then
    return array
  end
  local result = {}

  for i = 1, #array do
    if array[i] ~= nil then
      table.insert(result, array[i])
    end
  end

  return result
end

---Get the symbol for a platform
---@param name string
---@param platform "iOS" | "macOS" | "tvOS" | "watchOS" | "Simulator" | "DriverKit"
---@return string
local function symbol_for_platform(name, platform)
  if platform == "iOS" then
    return ""
  elseif platform == "macOS" or platform == "DriverKit" then
    return "󰇄"
  elseif platform == "tvOS" then
    return ""
  elseif platform == "watchOS" then
    return "󰢗"
  elseif platform == "iOS Simulator" then
    if string.find(name, "iPad") then
      return "󰓶"
    end
    if string.find(name, "Any iOS Simulator") then
      return "󰦧"
    else
      return ""
    end
  end
  return platform
end

---Format a destination for display in the UI
---@param destination Destination
---@return string
function M.format_destination(destination)
  local parts = {}
  local function wrap_in_parentheses(string)
    return "(" .. string .. ")"
  end
  if destination.platform then
    table.insert(parts, symbol_for_platform(destination.name, destination.platform))
  end
  table.insert(parts, destination.name)
  if destination.OS then
    table.insert(parts, wrap_in_parentheses(destination.OS))
  end
  if destination.variant then
    table.insert(parts, wrap_in_parentheses(destination.variant))
  end
  return table.concat(parts, " ")
end

---Format a destination for use in a build command
---@param destination Destination
function M.format_destination_for_build(destination)
  local keys = { "platform", "arch", "id" }
  local parts = {}
  for _, k in ipairs(keys) do
    local v = destination[k]
    if v ~= nil then
      table.insert(parts, k .. "=" .. v)
    end
  end
  return table.concat(parts, ",")
end

---Remove n components from the end of a path
---@param path string
---@param n number
---@return string
function M.remove_n_components(path, n)
  for i = 1, n do
    path = vim.fs.dirname(path)
  end
  return path
end

---@param opts? UtilOpts
function M.setup(opts)
  M.options = opts or {}
end

return M
