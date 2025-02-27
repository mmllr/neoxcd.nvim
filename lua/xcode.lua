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
---Parse the output of `xcodebuild` into Quickfix entry types
---@param type string
---@return QuickfixEntryType|nil
local function get_type(type)
  if type == "error" then
    return types.QuickfixEntryType.ERROR
  elseif type == "warning" then
    return types.QuickfixEntryType.WARNING
  else
    return nil
  end
end

---Parse the output of `xcodebuild` into an optional error message
---@param error_message string
---@return QuickfixEntry|nil
local function parse_error_message(error_message)
  local rex = require("rex_posix")
  local filename, line, column, type, message = rex.match(error_message, "^(.+):([0-9]+):([0-9]+): (error|warning): (.+)$")
  if filename and line and column and type and message then
    local lnum = tonumber(line)
    local col = tonumber(column)
    local qfixtype = get_type(type)
    if lnum == nil or col == nil or type == nil then
      return nil
    end
    return {
      filename = filename,
      lnum = lnum,
      col = col,
      type = qfixtype,
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
  project.append_options_if_needed(cmd, project.current_project)
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
  project.current_project.quickfixes = nil
  build = {
    variables = {},
    log = {},
  }
  local result = M.load_build_settings()
  if result ~= project.ProjectResult.SUCCESS then
    return result
  end
  local cmd = {
    "xcodebuild",
    "build",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    "id=" .. project.current_project.destination.id,
    "-configuration",
    "Debug",
  }
  result = nio.wrap(run_build, 2)(cmd)
  return result.code
end

---Builds the target
---@async @return number
function M.clean()
  if not project.current_project.scheme then
    return project.ProjectResult.NO_SCHEME
  end
  if not project.current_project.destination then
    return project.ProjectResult.NO_DESTINATION
  end
  local cmd = {
    "xcodebuild",
    "clean",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    "id=" .. project.current_project.destination.id,
  }
  local result = nio.wrap(run_build, 2)(cmd)
  if result.code == project.ProjectResult.SUCCESS then
    project.current_project.quickfixes = nil
    project.current_project.build_settings = nil
    project.current_target = nil
  end
  return result.code
end

---Loads the build settings
---@async
---@return number
function M.load_build_settings() -- TODO: this might be a local function
  if not project.current_project.scheme then
    return project.ProjectResult.NO_SCHEME
  end
  if not project.current_project.destination then
    return project.ProjectResult.NO_DESTINATION
  end
  local cmd = {
    "xcodebuild",
    "build",
    "-scheme",
    project.current_project.scheme,
    "-showBuildSettings",
    "-json",
    "-destination",
    "id=" .. project.current_project.destination.id,
  }
  local result = nio.wrap(util.run_job, 3)(cmd)
  if result.code == project.ProjectResult.SUCCESS and result.stdout then
    project.current_project.build_settings = parse_settings(result.stdout)
    update_build_target()
  end
  return result.code
end

return M
