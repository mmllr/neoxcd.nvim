local M = {}

---@type string[]
local xcodebuild_log = {}

---The exported variables from the xcodebuild output
---@type table
local build_vars = {}

---Parse the output of `xcodebuild` into exported variables
---@param line string
local function parse_exported_variables(line)
  local key, value = line:match("export%s+(%S+)%s*\\=%s*(.+)")
  if key and value then
    build_vars[key] = value
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

---The lines frobuild_logm the xcodebuild output
---@return string[]
function M.build_log()
  return xcodebuild_log
end

---Adds a line from the xcodebuild output to the build log
---@param line string
function M.add_build_log(line)
  table.insert(xcodebuild_log, line)
  parse_exported_variables(line)
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

---Parse the product after a successful build
---@return Target|nil
function M.build_target()
  if
    build_vars.PROJECT
    and build_vars.PRODUCT_NAME
    and build_vars.PRODUCT_BUNDLE_IDENTIFIER
    and build_vars.PRODUCT_SETTINGS_PATH
    and build_vars.PROJECT_FILE_PATH
  then
    local target = {
      name = build_vars.PRODUCT_NAME,
      bundle_id = build_vars.PRODUCT_BUNDLE_IDENTIFIER,
      module_name = build_vars.PRODUCT_MODULE_NAME,
      plist = build_vars.PRODUCT_SETTINGS_PATH,
      project = {
        name = build_vars.PROJECT,
        path = build_vars.PROJECT_FILE_PATH,
        type = "project",
      },
    }
    return target
  end
  return nil
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
