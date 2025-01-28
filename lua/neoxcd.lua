local spinner = require("spinner")
local nio = require("nio")
local util = require("util")
local xcode = require("xcode")
local destination_mapping = {}
local selected_scheme = nil
---@type string[]
local build_output = {}

---@async
---@param directory string
---@return string|nil
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

--- Returns the path to the Xcode workspace or project or Package.swift file in the current directory
---@async
---@return Project|nil
local function project_file()
  local files = vim.fs.find(function(name, path)
    return vim.endswith(name, ".xcworkspace") or vim.endswith(name, ".xcodeproj") or vim.endswith(name, "Package.swift")
  end, { limit = 3 })

  for _, file in ipairs(files) do
    if vim.endswith(file, "xcworkspace") then
      return { path = file, type = "workspace" }
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "xcodeproj") then
      return { path = file, type = "project" }
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "Package.swift") then
      return { path = file, type = "package" }
    end
  end
  return nil
end

--- Find the Xcode workspace or project file in the current directory
--- When no result is found, return empty table (Swift package projects do not have a workspace or project file)
---@async
---@return table|nil
local function find_build_options()
  local project = project_file()
  if project ~= nil then
    if project.type == "package" then
      return {}
    end
    local type = project.type
    return { "-" .. type, project.path }
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

---Run an external command
---@async
---@param cmd string
---@param args string[]|nil
---@param detached boolean|nil
local function run_external_cmd(cmd, args, detached)
  local result = nio.process.run({
    cmd = cmd,
    args = args,
    detached = detached,
  })
  if result == nil then
    return nil
  end
  local output = result.stdout.read()
  result.close()
  return output
end

---@param callback function
local function buildit(cmd, callback)
  ---@type vim.SystemOpts
  vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      if data then
        xcode.parse_quickfix_list(data)
      end
    end,
  }, function(obj)
    callback(obj.code)
  end)
end

local buildit_async = nio.wrap(buildit, 2)

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
    return xcode.parse_destinations(output)
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
  if output == nil or opts == nil then
    vim.notify("No schemes found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  local schemes = xcode.parse_schemes(output)
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
      "No destination selected, use Neoxcd destination to choose a destination",
      vim.log.levels.ERROR,
      { id = "Neoxcd", title = "Neoxcd" }
    )
    return
  end
  local start_time = os.time()
  spinner.start("Building " .. scheme .. "...")
  --- TODO: query available configurations instead of hardcoding "Debug"
  local cmd = {
    "xcodebuild",
    "build",
    "-scheme",
    scheme,
    "-destination",
    util.format_destination_for_build(destination_mapping[scheme]),
    "-configuration",
    "Debug",
    -- "-quiet",
  }
  local code = buildit_async(cmd)
  nio.scheduler()
  spinner.stop()
  if code == 0 then
    local end_time = os.time()
    local msg = string.format(
      "Build succeeded in %.2f seconds, target: " .. vim.inspect(xcode.build_target()),
      os.difftime(end_time, start_time)
    )
    vim.notify(msg, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  else
    vim.notify("Build failed", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
end

---Starts the simulator
---@async
---@param id string
local function open_in_simulator(id)
  spinner.start("Opening in simulator...")
  local result = run_external_cmd("xcrun", { "simctl", "boot", id })
  nio.scheduler()
  if result == nil then
    spinner.stop()
    vim.notify("Failed to start simulator", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  local xcode_path = run_external_cmd("xcode-select", { "-p" })
  if xcode_path == nil then
    spinner.stop()
    vim.notify("Failed to find Xcode path", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  local simulator_path = string.gsub(xcode_path, "\n", "") .. "/Applications/Simulator.app"
  local open = run_external_cmd("open", { simulator_path })
  spinner.stop()
  if open == nil then
    nio.scheduler()
    vim.notify("Failed to open simulator", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
end

---Opens the current project in Xcode
---@async
local function open_in_xcode()
  spinner.start("Opening in Xcode...")
  local xcode_path = run_external_cmd("xcode-select", { "-p" })
  nio.scheduler()
  if xcode_path == nil then
    spinner.stop()
    vim.notify("Failed to find Xcode path", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  local project = project_file()
  xcode_path = util.remove_n_components(xcode_path, 2)
  if project ~= nil then
    local open = run_external_cmd("open", { xcode_path, project.path })
  end
  nio.scheduler()
  spinner.stop()
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
  open_in_simulator = nio.create(function()
    local scheme = selected_scheme or current_scheme(nio.fn.getcwd())
    nio.scheduler()
    local destination = destination_mapping[scheme]
    if destination == nil then
      vim.notify(
        "No destination selected, use NeoxcdSelectDestination to choose a destination",
        vim.log.levels.ERROR,
        { id = "Neoxcd", title = "Neoxcd" }
      )
      return
    end
    open_in_simulator(destination.id)
  end),
  open_in_xcode = nio.create(open_in_xcode),
}
