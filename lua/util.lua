local nio = require("nio")

local M = {}

---Find files with a specific extension in a directory
---@param extension string
---@param directory string
---@return string[]
function M.find_files_with_extension(extension, directory)
  local pattern = directory .. "/*." .. extension
  local files = nio.fn.glob(pattern, false, true) -- Get a list of files
  return files
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

local function extract_fields(entry)
  -- { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:c0ffeec0-c0ffeec0ffeec0ff, name:My Mac }
  local result = {}
  for entry in vim.gsplit(entry, ", ", { plain = true }) do
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
  for k, v in pairs(destination) do
    if vim.tbl_contains(keys, k) then
      table.insert(parts, k .. "=" .. v)
    end
  end
  return table.concat(parts, ",")
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

return M
