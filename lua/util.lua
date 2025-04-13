local nio = require("nio")

---@class UtilOpts
---@field run_cmd? fun(cmd: string[], on_stdout: fun(error: string?, data: string?)|nil, on_exit: fun(obj: vim.SystemCompleted))
---@field run_dap? fun(config: dap.Configuration)
---@field read_file? async fun(path: string): string?
---@field write_file? async fun(path: string, contents: string): boolean

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
---@param on_stdout fun(err: string?, data: string?)|nil
---@param on_exit fun(obj: vim.SystemCompleted)
function M.run_job(cmd, on_stdout, on_exit)
  -- print("Running command: " .. table.concat(cmd, " "))
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

---Read a file
---@async
---@param path string
---@return string?
function M.read_file(path)
  if M.options.read_file ~= nil and type(M.options.read_file) == "function" then
    return M.options.read_file(path)
  end
  local file = nio.file.open(path, "r")

  local contents
  if file then
    contents = file.read(nil, 0)
    file.close()
  end
  return contents
end

---Writes a file
---@async
---@param path string
---@param content string
---@return boolean
function M.write_file(path, content)
  if M.options.write_file ~= nil and type(M.options.write_file) == "function" then
    return M.options.write_file(path, content)
  end
  local file = nio.file.open(path, "w+")
  if file then
    file.write(content)
    file.close()
    return true
  end
  return false
end

---Gets the current working directory
---@return string The current working directory
function M.get_cwd()
  return vim.fn.getcwd()
end

---List the files in a directory
---@param directory string The directory to list the files in
---@return string[] The list of files
function M.list_files(directory)
  local files = {}
  local handle = vim.uv.fs_scandir(directory)
  if handle then
    while true do
      local name, type = vim.uv.fs_scandir_next(handle)
      if not name then
        break
      end
      table.insert(files, name)
    end
  end
  return files
end

---Check if a list contains a value
---@param list any[]
---@param predicate fun(value: any): boolean
---@return boolean
function M.list_contains(list, predicate)
  for _, v in ipairs(list) do
    if predicate(v) then
      return true
    end
  end
  return false
end

---Finds the first value in a list that matches a predicate
---@param list any[]
---@param predicate fun(value: any): boolean
---return any|nil
function M.find_first(list, predicate)
  for _, v in ipairs(list) do
    if predicate(v) then
      return v
    end
  end
  return nil
end

function M.has_suffix(str, suffix)
  return str:sub(-#suffix) == suffix
end

---Concatenates multiple tables
---@param ... any[]
---@return any[]
function M.concat(...)
  local result = {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if type(t) ~= "table" then
      error("Expected table, got " .. type(t))
    end
    for _, v in ipairs(t) do
      table.insert(result, v)
    end
  end
  return result
end

return M
