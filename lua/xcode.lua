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
      add_build_log(data)
      add_quickfix(data)
    end
  end, callback)
end

---Parse the output of `xcodebuild -list -json` into a table of schemes
---@param input string
---@return string[]
local function parse_schemes(input)
  local schemes = {}
  -- vim.notify(input, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
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

---Load the schemes for the current project
---@async
---@return number
function M.load_schemes()
  local p = project.current_project
  if not p then
    return -1
  end
  local opts = project.build_options_for_project(p)
  local cmd = util.concat({ "xcodebuild", "-list", "-json" }, opts)
  vim.notify(vim.inspect(cmd), vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  local result = nio.wrap(util.run_job, 3)(cmd, nil)
  vim.notify(vim.inspect(result), vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  if result.code == 0 and result.stdout ~= nil then
    -- vim.notify(result.stdout, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
    project.current_project.schemes = parse_schemes(result.stdout)
  end
  return result.code
end

---Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
local function parse_destinations(text)
  local destinations = {}

  for block in text:gmatch("{(.-)}") do
    local destination = extract_fields(vim.trim(block))

    if destination ~= nil then
      table.insert(destinations, destination)
    end
  end

  return destinations
end

---Loads selects a destination for the current scheme
---@async
---@return number
function M.load_destinations()
  local p = project.current_project
  if not p or not p.scheme then
    return -1
  end

  local opts = project.build_options_for_project(p)
  local result = nio.wrap(util.run_job, 3)(
    util.concat({ "xcodebuild", "-showdestinations", "-scheme", p.scheme, "-quiet" }, opts),
    nil
  )
  if result.code == 0 and result.stdout then
    project.current_project.destinations = parse_destinations(result.stdout)
  end
  return result.code
end

---selects a scheme
---@async
---@param scheme string
---@return number
function M.select_scheme(scheme)
  local p = project.current_project
  if not p or not p.schemes and not vim.list_contains(p.schemes, scheme) then
    return -1
  end
  local opts = project.build_options_for_project(p)
  local result =
    nio.wrap(util.run_job, 3)(util.concat({ "xcode-build-server", "config", "-scheme", scheme }, opts), nil)
  if result.code == 0 then
    project.current_project.scheme = scheme
  end
  return result.code
end

return M
