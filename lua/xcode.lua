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

---Extracts filename, line and column from a source URL string
---@param string string
---@return string|nil, number|nil, number|nil
local function parse_source_url(string)
  -- file:///Users/user/Document.swift#EndingColumnNumber=19&EndingLineNumber=15&StartingColumnNumber=19&StartingLineNumber=15&Timestamp=762641443.309049-- Extract filename

  local filename = string:match("file://([^#]+)")
  local line = string:match("StartingLineNumber=(%d+)")
  local column = string:match("StartingColumnNumber=(%d+)")
  if line then
    line = tonumber(line)
  end
  if column then
    column = tonumber(column)
  end
  return filename, line, column
end

---Parse the output of `xcodebuild` into an optional error message
---@param json string The json output of `xcodebuild`
---@return QuickfixEntry|nil
local function parse_build_results(json)
  if project.current_project.quickfixes == nil then
    project.current_project.quickfixes = {}
  end
  local data = vim.json.decode(json)
  for _, error in ipairs(data["errors"]) do
    if error["sourceURL"] then
      local filename, lnum, col = parse_source_url(error["sourceURL"])
      if filename and lnum and col then
        table.insert(project.current_project.quickfixes, {
          filename = filename,
          lnum = lnum + 1,
          col = col + 1,
          type = types.QuickfixEntryType.ERROR,
          text = error["message"],
        })
      end
    end
  end
  for _, warning in ipairs(data["warnings"]) do
    if warning["sourceURL"] then
      local filename, lnum, col = parse_source_url(warning["sourceURL"])
      if filename and lnum and col then
        table.insert(project.current_project.quickfixes, {
          filename = filename,
          lnum = lnum + 1,
          col = col + 1,
          type = types.QuickfixEntryType.WARNING,
          text = warning["message"],
        })
      end
    end
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

---@param callback fun(code: vim.SystemCompleted)
local function run_build(cmd, callback)
  project.append_options_if_needed(cmd, project.current_project)
  util.run_job(cmd, function(_, data)
    if data then
      for line in data:gmatch("[^\n]+") do
        add_build_log(line)
      end
    end
  end, callback)
end

---Builds the target
---@async
---@param forTesting boolean|nil
---@return number
function M.build(forTesting)
  project.current_project.quickfixes = nil
  build = {
    variables = {},
    log = {},
  }
  local result = M.load_build_settings()
  if result ~= project.ProjectResult.SUCCESS then
    return result
  end

  local run_job = nio.wrap(util.run_job, 3)
  nio.scheduler()
  local result_bundle_path = util.get_cwd() .. "/.neoxcd/build.xcresult"
  run_job({ "rm", "-rf", result_bundle_path })
  local cmd = {
    "xcodebuild",
    forTesting and "build-for-testing" or "build",
    "-scheme",
    project.current_project.scheme,
    "-destination",
    "id=" .. project.current_project.destination.id,
    "-configuration",
    "Debug",
    "-resultBundlePath",
    result_bundle_path,
  }
  local build_result = nio.wrap(run_build, 2)(cmd)
  result = run_job({
    "xcrun",
    "xcresulttool",
    "get",
    "build-results",
    "--path",
    result_bundle_path,
  })

  if result.code == project.ProjectResult.SUCCESS and result.stdout then
    parse_build_results(result.stdout)
  end
  return build_result.code
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
