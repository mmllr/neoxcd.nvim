local spinner = require("spinner")
local nio = require("nio")
local util = require("util")
local destination_mapping = {}
local ui = require("ui")

local selected_scheme = nil

---@async
---@param directory string
---@return string?
local function current_scheme(directory)
  local file = nio.file.open(directory .. "/buildServer.json")
  if not file then
    return nil
  end
  local content, error = file.read(nil, 0)
  file.close()
  if content == nil or error then
    return nil
  end
  local decoded = vim.json.decode(content)
  if decoded and decoded["scheme"] then
    return decoded["scheme"]
  else
    return nil
  end
end

---@async
local load_schemes = function(opts)
  local build = nio.process.run({
    cmd = "xcodebuild",
    args = util.concat({ "-list", "-json" }, opts or {}),
  })
  if build == nil then
    return nil
  end
  local output = build.stdout.read()
  build.close()
  return output
end

--- Find the Xcode workspace or project file in the current directory
--- When no result is found, return empty table (Swift package projects do not have a workspace or project file)
---@return table?
local function find_build_options()
  local workspace = util.find_files_with_extension("xcworkspace", nio.fn.getcwd())
  if #workspace > 0 then
    return { "-workspace", workspace[1] }
  end
  local project = util.find_files_with_extension("xcodeproj", nio.fn.getcwd())
  if #project > 0 then
    return { "-project", project[1] }
  end
  local files = nio.fn.glob(nio.fn.getcwd() .. "/Package.swift", false, true) -- Get a list of files
  if files and #files > 0 then
    return {}
  end
  return nil
end

---@async
local function update_xcode_build_config(scheme, opts)
  local build = nio.process.run({
    cmd = "xcode-build-server",
    args = util.concat({ "config", "-scheme", scheme }, opts or {}),
  })
  if build == nil then
    return false
  end
  return build.result(true) == 0
end

local function show_ui(schemes, opts, callback)
  vim.ui.select(schemes, opts, callback)
end

local select_async = nio.wrap(show_ui, 3)

---@async
local function run_external_cmd(cmd, args)
  local result = nio.process.run({
    cmd = cmd,
    args = args,
  })
  if result == nil then
    return nil
  end
  local output = result.stdout.read()
  result.close()
  return output
end

---@async
local function run_build(cmd, args)
  local buildLog = nio.file.open(nio.fn.getcwd() .. "/build.log", "w")
  local result = nio.process.run({
    cmd = cmd,
    args = args,
    stdout = buildLog,
  })
  if result == nil then
    return -1, nil
  end
  local retval, _ = result.result(true)
  return retval
end

---@async
local function show_destinations(scheme, opts)
  local output =
    run_external_cmd("xcodebuild", util.concat({ "-showdestinations", "-scheme", scheme, "-quiet" }, opts or {}))
  if output then
    return util.parse_destinations(output)
  else
    return nil
  end
end

--- Shows a list of schemes and updates the xcode-build-server config
---@async
local select_schemes = function()
  spinner.start("Loading schemes...")
  local opts = find_build_options()
  local output = load_schemes(opts)
  nio.scheduler()
  spinner.stop()
  local schemes = {}
  if output == nil or opts == nil then
    vim.notify("No schemes found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  else
    schemes = util.parse_schemes(output)
  end
  local selection = select_async(schemes, {
    prompt = "Select a scheme",
  })
  if selection then
    spinner.start("Updating xcode-build-server config...")
    local success
    if #opts == 0 then
      success = true
    else
      success = update_xcode_build_config(selection, opts)
    end
    selected_scheme = selection
    nio.scheduler()
    spinner.stop()
    if success then
      vim.notify("Selected scheme: " .. selection, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
    else
      vim.notify("Failed to select scheme: " .. selection, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
  end
end

--- Selects a destination for the current scheme
---@async
local function select_destination()
  local scheme = selected_scheme or current_scheme(nio.fn.getcwd())
  nio.scheduler()
  if scheme then
    spinner.start("Loading destinations for scheme: " .. scheme .. "...")
    local opts = find_build_options()
    local destinations = show_destinations(scheme, opts)
    spinner.stop()
    if #destinations > 0 and destinations then
      nio.scheduler()
      local selection = select_async(destinations, {
        prompt = "Select a destination",
        format_item = util.format_destination,
      })
      destination_mapping[scheme] = selection
    else
      vim.notify("No destinations found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
  else
    vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
end

---Cleans the project
---@async
local function clean()
  spinner.start("Cleaning project...")
  local scheme = selected_scheme or current_scheme(nio.fn.getcwd())
  nio.scheduler()
  if scheme == nil then
    vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  if destination_mapping[scheme] == nil then
    vim.notify(
      "No destination selected, use NeoxcdSelectDestination to choose a destination",
      vim.log.levels.ERROR,
      { id = "Neoxcd", title = "Neoxcd" }
    )
    return
  end
  local result = run_external_cmd("xcodebuild", {
    "clean",
    "-scheme",
    scheme,
    "-destination",
    util.format_destination_for_build(destination_mapping[scheme]),
  })
  nio.scheduler()
  spinner.stop()
  if result ~= nil then
    vim.notify("Project cleaned", vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  else
    vim.notify("Failed to clean project", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
end

---Builds the project
---@async
local function build()
  local opts = find_build_options()
  if opts == nil then
    vim.notify("No Xcode project or workspace found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  local scheme = selected_scheme or current_scheme(nio.fn.getcwd())
  nio.scheduler()
  if destination_mapping[scheme] == nil then
    vim.notify(
      "No destination selected, use NeoxcdSelectDestination to choose a destination",
      vim.log.levels.ERROR,
      { id = "Neoxcd", title = "Neoxcd" }
    )
    return
  end
  local start_time = os.time()
  spinner.start("Building " .. scheme .. "...")
  --- TODO: query available configurations instead of hardcoding "Debug"
  local cmd = {
    "build",
    "-scheme",
    scheme,
    "-destination",
    util.format_destination_for_build(destination_mapping[scheme]),
    "-configuration",
    "Debug",
    "-quiet",
  }
  local code = run_build("xcodebuild", util.concat(cmd, opts))
  nio.scheduler()
  spinner.stop()
  if code == 0 then
    local end_time = os.time()
    local msg = string.format("Build succeeded in %.2f seconds", os.difftime(end_time, start_time))
    vim.notify(msg, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  else
    vim.notify("Build failed", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
  local output = nio.file.open(nio.fn.getcwd() .. "/build.log")
  if output then
    local content, error = output.read(nil, 0)
    output.close()
    if content and not error then
      nio.scheduler()
      ui.show_window_with_content(content)
    end
  end
end

return {
  current_scheme = current_scheme,
  setup = nio.create(function()
    local scheme = current_scheme(nio.fn.getcwd())
    if scheme then
      selected_scheme = scheme
    end
  end),
  clean = nio.create(clean),
  build = nio.create(build),
  select_schemes = nio.create(select_schemes),
  select_destination = nio.create(select_destination),
}
