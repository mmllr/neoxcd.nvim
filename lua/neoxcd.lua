local spinner = require("spinner")
local nio = require("nio")
local project = require("project")
local util = require("util")
local xcode = require("xcode")

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

--- Shows a list of schemes and updates the xcode-build-server config
---@async
local select_schemes = function()
  if project.current_project == nil then
    vim.notify("No project loaded", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  if #project.current_project.schemes == 0 then
    spinner.start("Loading schemes...")
    local result = project.load_schemes()
    nio.scheduler()
    spinner.stop()
    local schemes = project.current_project.schemes
    if result ~= 0 or #schemes == 0 then
      vim.notify("No schemes found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
      return
    end
  end
  local selection = select_async(project.current_project.schemes, {
    prompt = "Select a scheme",
  })
  local result
  if selection ~= nil then
    spinner.start("Updating xcode-build-server config...")
    result = project.select_scheme(selection)
  end
  nio.scheduler()
  spinner.stop()
  if result == 0 then
    vim.notify("Selected scheme: " .. selection, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  else
    vim.notify("Failed to select scheme: " .. selection, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
end

--- Selects a destination for the current scheme
---@async
local function select_destination()
  if project.current_project == nil or project.current_project.scheme == nil then
    vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
  if project.destinations() == nil then
    spinner.start("Loading destinations for scheme: " .. project.current_project.scheme .. "...")
    local result = project.load_destinations()
    spinner.stop()
    if result ~= 0 or project.destinations() == nil then
      vim.notify("Failed to load destinations", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
      return
    end
    nio.scheduler()
  end
  local _, idx = select_async(project.destinations(), {
    prompt = "Select a destination",
    format_item = util.format_destination,
  })
  project.select_destination(idx)
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
  local start_time = os.time()
  spinner.start("Building project...")
  local code = xcode.build()
  nio.scheduler()
  spinner.stop()
  if code == 0 then
    local end_time = os.time()
    local msg = string.format("Build succeeded in %.2f seconds", os.difftime(end_time, start_time))
    vim.notify(msg, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
    if project.current_project.quickfixes then
      vim.fn.setqflist(project.current_project.quickfixes, "r")
    end
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
  setup = function(options)
    project.load()
  end,
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
