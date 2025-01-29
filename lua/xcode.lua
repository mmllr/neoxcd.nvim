local nio = require("nio")
local util = require("util")
local project = require("project")
local M = {}

---@private
---@class Build
---@field variables? table
---@field log? string[]
local build = {}

---Parse the output of `xcodebuild` into exported variables
---@param line string
local function parse_exported_variables(line)
  if build.variables == nil then
    build.variables = {}
  end
  local key, value = line:match("export%s+(%S+)%s*\\=%s*(.+)")
  if key and value then
    build.variables[key] = value
  end
end

local function extract_fields(destination)
  -- { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:c0ffeec0-c0ffeec0ffeec0ff, name:My Mac }
  local result = {}
  for entry in vim.gsplit(destination, ", ", { plain = true }) do
    local key, value = entry:match("(%w+):(.+)")
    if key and value then
      if key == "error" then
        return nil
      end
      result[key] = value
    end
  end
  if vim.tbl_isempty(result) then
    return nil
  end
  return result
end

---Parse the output of `xcodebuild` into an optional error message
---@param error_message string
---@return QuickfixEntry|nil
local function parse_error_message(error_message)
  local pattern = "([^:]+):(%d+):(%d+): (%a+): (.+)"
  local filename, line, column, type, message = error_message:match(pattern)
  local function get_type()
    if type == "error" then
      return "E"
    elseif type == "warning" then
      return "W"
    else
      return "I"
    end
  end
  if filename and line and column and type and message then
    local lnum = tonumber(line)
    local col = tonumber(column)
    if lnum == nil or col == nil then
      return nil
    end
    ---@type QuickfixEntry
    return {
      filename = filename,
      lnum = lnum,
      col = col,
      type = get_type(),
      text = message,
    }
  else
    return nil
  end
end

---Parse the product after a successful build
local function update_build_target()
  if project.current_project == nil then
    return
  end
  if build.variables.PROJECT and build.variables.PROJECT_FILE_PATH then
    project.current_project.name = build.variables.PROJECT
    project.current_project.path = build.variables.PROJECT_FILE_PATH
  end
  if
    build.variables.PRODUCT_NAME
    and build.variables.PRODUCT_BUNDLE_IDENTIFIER
    and build.variables.PRODUCT_SETTINGS_PATH
  then
    project.current_target = {
      name = build.variables.PRODUCT_NAME,
      bundle_id = build.variables.PRODUCT_BUNDLE_IDENTIFIER,
      module_name = build.variables.PRODUCT_MODULE_NAME,
      plist = build.variables.PRODUCT_SETTINGS_PATH,
    }
  end
end

---@param callback fun(code: vim.SystemCompleted)
local function run_build(cmd, callback)
  util.run_job(cmd, callback, function(_, data)
    if data then
      M.add_build_log(data)
    end
  end)
end

---Builds the target
---@async
---@return number
function M.build()
  if not project.current_project.scheme then
    return -1
  end
  if not project.current_project.destination then
    return -2
  end

  build = {
    variables = {},
    log = {},
  }

  local cmd = {
    "xcodebuild",
    "build",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    util.format_destination_for_build(project.current_project.destination),
    "-configuration",
    "Debug",
    -- "-quiet",
  }
  -- spinner.start("Building " .. project.current_project.scheme .. "...")
  local result = nio.wrap(run_build, 2)(cmd)
  update_build_target()
  -- spinner.stop()
  return result.code
end

---Adds a line from the xcodebuild output to the build log
---@param line string
function M.add_build_log(line)
  if build.log == nil then
    build.log = {}
  end
  table.insert(build.log, line)
  parse_exported_variables(line)
  update_build_target()
end

function M.load_schemes()
  local p = project.current_project
  if p == nil then
    return
  end
  local opts = project.build_options_for_project(p)
  util.run_job(util.concat({ "xcodebuild", "-list", "-json" }, opts), function(code) end)
end

---Parse the output of `xcodebuild -list -json` into a table of schemes
---@param input string
---@return string[]
function M.parse_schemes(input)
  local schemes = {}
  local data = vim.json.decode(input)
  if data then
    local parent_key
    if data["project"] ~= nil then
      parent_key = "project"
    elseif data["workspace"] ~= nil then
      parent_key = "workspace"
    end
    if parent_key and data[parent_key]["schemes"] ~= nil then
      for _, scheme in ipairs(data[parent_key]["schemes"]) do
        table.insert(schemes, scheme)
      end
    end
  end
  return schemes
end

---Parse the output of `` into a table of build settings
---@param input string
---@return QuickfixEntry[]
function M.parse_quickfix_list(input)
  local results = {}
  local lines = vim.split(input, "\n", { trimempty = true })
  for _, line in ipairs(lines) do
    if parse_error_message(line) then
      table.insert(results, parse_error_message(line))
    end
  end
  return results
end

---Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
function M.parse_destinations(text)
  local destinations = {}

  for block in text:gmatch("{(.-)}") do
    local destination = extract_fields(vim.trim(block))

    if destination ~= nil then
      table.insert(destinations, destination)
    end
  end

  return destinations
end

return M
