local nio = require("nio")
local util = require("util")
local M = {}

---@type DestinationCache
local destinations = {}

---Parse the output of `xcodebuild -list -json` into a table of schemes
---@param input string
---@return string[]
local function parse_schemes(input)
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

---Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
local function parse_destinations(text)
  local result = {}

  for block in text:gmatch("{(.-)}") do
    local destination = extract_fields(vim.trim(block))

    if destination ~= nil then
      table.insert(result, destination)
    end
  end

  return result
end

---@type Project|nil
M.current_project = nil

---@type Target|nil
M.current_target = nil

---Loads the project file in the current directory
function M.load()
  local files = vim.fs.find(function(name, path)
    return vim.endswith(name, ".xcworkspace") or vim.endswith(name, ".xcodeproj") or vim.endswith(name, "Package.swift")
  end, { limit = 1 })

  for _, file in ipairs(files) do
    if vim.endswith(file, "xcworkspace") then
      M.current_project = { path = file, type = "workspace", schemes = {}, destinations = {} }
      return
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "xcodeproj") then
      M.current_project = { path = file, type = "project", schemes = {}, destinations = {} }
      return
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "Package.swift") then
      M.current_project = { path = file, type = "package", schemes = {}, destinations = {} }
      return
    end
  end
  M.current_project = nil
end

---Returns the builld options for a project
---@param project Project
---@return string[]
function M.build_options_for_project(project)
  if project.type == "package" then
    return {}
  end
  return { "-" .. project.type, project.path }
end

--- Find the Xcode workspace or project file in the current directory
--- When no result is found, return empty table (Swift package projects do not have a workspace or project file)
---@return string[]|nil
function M.find_build_options()
  if M.current_project ~= nil then
    return M.build_options_for_project(M.current_project)
  end
  return nil
end

---Load the schemes for the current project
---@async
---@return number
function M.load_schemes()
  local p = M.current_project
  if not p then
    return -1
  end
  local opts = M.build_options_for_project(p)
  local result = nio.wrap(util.run_job, 3)(util.concat({ "xcodebuild", "-list", "-json" }, opts), nil)
  if result.code == 0 and result.stdout ~= nil then
    M.current_project.schemes = parse_schemes(result.stdout)
  end
  return result.code
end

---selects a scheme
---@async
---@param scheme string
---@return number
function M.select_scheme(scheme)
  local p = M.current_project
  if not p or not p.schemes and not vim.list_contains(p.schemes, scheme) then
    return -1
  end
  if p.scheme == scheme then
    return 0
  end
  local opts = M.build_options_for_project(p)
  local result =
    nio.wrap(util.run_job, 3)(util.concat({ "xcode-build-server", "config", "-scheme", scheme }, opts), nil)
  if result.code == 0 then
    M.current_project.scheme = scheme
  end
  return result.code
end

---Loads selects a destination for the current scheme
---@async
---@return number
function M.load_destinations()
  local p = M.current_project
  if not p or not p.scheme then
    return -1
  end

  local opts = M.build_options_for_project(p)
  local result = nio.wrap(util.run_job, 3)(
    util.concat({ "xcodebuild", "-showdestinations", "-scheme", p.scheme, "-quiet" }, opts),
    nil
  )
  if result.code == 0 and result.stdout then
    destinations[p.scheme] = parse_destinations(result.stdout)
  end
  return result.code
end

---Select a destination
---@param index number
function M.select_destination(index)
  if M.current_project == nil or M.current_project.scheme == nil or destinations[M.current_project.scheme] == nil then
    return
  end
  M.current_project.destination = destinations[M.current_project.scheme][index]
end

---Returns the available destinations for the currently selected scheme
---@return Destination|nil Nil when no project is loaded or no scheme is selected
function M.destinations()
  return M.current_project and M.current_project.scheme and destinations[M.current_project.scheme] or nil
end

return M
