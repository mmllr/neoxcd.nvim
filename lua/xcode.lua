local nio = require("nio")
local util = require("util")
local project = require("project")
local types = require("types")
local M = {}

---@private
---@class Build
---@field log? string[]
local build = {}

---Parse the output of `xcodebuild` into build settings
---@param input string json with build settings
---@return table<string, string>|nil
local function parse_settings(input)
  local data = vim.json.decode(input)
  if data and data[1] and data[1] then
    return data[1]["buildSettings"]
  end
  return data
end

local function get_type(type)
  if type == "error" then
    return "E"
  elseif type == "warning" then
    return "W"
  else
    return "I"
  end
end

---Parse the output of `xcodebuild` into an optional error message
---@param error_message string
---@return QuickfixEntry|nil
local function parse_error_message(error_message)
  local rex = require("rex_posix")
  local filename, line, column, type, message =
    rex.match(error_message, "^(.+):([0-9]+):([0-9]+): (error|warning): (.+)$")
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
      type = get_type(type),
      text = message,
    }
  else
    return nil
  end
end

---Parse the product after a successful build
local function update_build_target()
  local variables = project.current_project.build_settings
  if variables == nil then
    return
  end
  if variables.PROJECT and variables.PROJECT_FILE_PATH then
    project.current_project.name = variables.PROJECT
    project.current_project.path = variables.PROJECT_FILE_PATH
  end
  if
    variables.PRODUCT_NAME
    and variables.PRODUCT_BUNDLE_IDENTIFIER
    and variables.PRODUCT_SETTINGS_PATH
    and variables.FULL_PRODUCT_NAME
    and variables.TARGET_BUILD_DIR
  then
    project.current_target = {
      name = variables.PRODUCT_NAME,
      bundle_id = variables.PRODUCT_BUNDLE_IDENTIFIER,
      module_name = variables.PRODUCT_MODULE_NAME,
      plist = variables.PRODUCT_SETTINGS_PATH,
      app_path = variables.TARGET_BUILD_DIR .. "/" .. variables.FULL_PRODUCT_NAME,
    }
  end
end

---Adds a line from the xcodebuild output to the build log
---@param line string
local function add_build_log(line)
  if build.log == nil then
    build.log = {}
  end
  table.insert(build.log, line)
end

---@param line string
local function add_quickfix(line)
  if not project.current_project then
    return
  end
  if project.current_project.quickfixes == nil then
    project.current_project.quickfixes = {}
  end
  local entry = parse_error_message(line)
  if entry then
    table.insert(project.current_project.quickfixes, entry)
  end
end

---@param callback fun(code: vim.SystemCompleted)
local function run_build(cmd, callback)
  util.run_job(cmd, function(_, data)
    if data then
      for line in data:gmatch("[^\n]+") do
        add_build_log(line)
        add_quickfix(line)
      end
    end
  end, callback)
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

  project.current_project.quickfixes = nil
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
  }
  local result = nio.wrap(run_build, 2)(cmd)
  return result.code
end

---Builds the target
---@async
---@return number
function M.clean()
  if not project.current_project.scheme then
    return -1
  end
  if not project.current_project.destination then
    return -2
  end
  local cmd = {
    "xcodebuild",
    "clean",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    util.format_destination_for_build(project.current_project.destination),
  }
  local result = nio.wrap(run_build, 2)(cmd)
  return result.code
end

---Loads the build settings
---@async
---@return number
function M.load_build_settings()
  if not project.current_project.scheme then
    return -1
  end
  if not project.current_project.destination then
    return -2
  end
  local cmd = {
    "xcodebuild",
    "build",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    util.format_destination_for_build(project.current_project.destination),
    "-configuration",
    "Debug",
    "-showBuildSettings",
    "-json",
  }
  local result = nio.wrap(util.run_job, 3)(cmd)
  if result.code == 0 and result.stdout then
    project.current_project.build_settings = parse_settings(result.stdout)
    update_build_target()
  end
  return result.code
end
return M
