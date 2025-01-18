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

---Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
function M.parse_destinations(text)
  local destinations = {}

  -- Pattern to match each destination block
  for block in text:gmatch("{(.-)}") do
    local destination = {}

    -- Extract key-value pairs within the block
    for key, value in block:gmatch("(%w+):([^,]+)") do
      -- Remove any surrounding spaces or brackets
      key = key:match("^%s*(.-)%s*$")
      value = value:match("^%s*(.-)%s*$")

      -- Handle special cases for lists and numbers
      if value:match("^%[.*%]$") then
        -- Convert lists like [iPad,iPhone] into Lua tables
        local list = {}
        for item in value:gmatch("[^%[%],]+") do
          table.insert(list, item)
        end
        value = list
      elseif tonumber(value) then
        value = tonumber(value) -- Convert numeric strings to numbers
      elseif value == "nil" then
        value = nil -- Convert "nil" strings to actual nil
      end

      destination[key] = value
    end

    table.insert(destinations, destination)
  end

  return destinations
end

---Format a destination for display in the UI
---@param destination Destination
---@return string
function M.format_destination(destination)
  local parts = { destination.name }
  if destination.platform then
    table.insert(parts, destination.platform)
  end
  if destination.arch then
    table.insert(parts, destination.arch)
  end
  if destination.OS then
    table.insert(parts, destination.OS)
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
