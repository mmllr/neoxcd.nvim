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
    and build.variables.FULL_PRODUCT_NAME
    and build.variables.TARGET_BUILD_DIR
  then
    project.current_target = {
      name = build.variables.PRODUCT_NAME,
      bundle_id = build.variables.PRODUCT_BUNDLE_IDENTIFIER,
      module_name = build.variables.PRODUCT_MODULE_NAME,
      plist = build.variables.PRODUCT_SETTINGS_PATH,
      app_path = build.variables.TARGET_BUILD_DIR .. "/" .. build.variables.FULL_PRODUCT_NAME,
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
  parse_exported_variables(line)
  update_build_target()
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
  update_build_target()
  vim.notify(vim.inspect(project.current_target), vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
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

return M
