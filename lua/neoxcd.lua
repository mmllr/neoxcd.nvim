local spinner = require("spinner")
local nio = require("nio")
local project = require("project")
local util = require("util")
local xcode = require("xcode")

local function show_ui(schemes, opts, callback)
  vim.ui.select(schemes, opts, callback)
end

local select_async = nio.wrap(show_ui, 3)

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
  local result = xcode.clean()
  spinner.stop()
  if result == 0 then
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

---Opens the current project in Xcode
---@async
local function open_in_xcode()
  spinner.start("Opening in Xcode...")
  local result = project.open_in_xcode()
  nio.scheduler()
  spinner.stop()
  if result ~= 0 then
    vim.notify("Failed to open project in Xcode", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    return
  end
end

return {
  setup = function(options)
    project.load()
  end,
  clean = nio.create(clean),
  build = nio.create(build),
  select_schemes = nio.create(select_schemes),
  select_destination = nio.create(select_destination),
  run = nio.create(function()
    spinner.start("Opening in simulator...")
    local result = project.run()
    spinner.stop()
    if result ~= 0 then
      vim.notify(
        "Failed to open project in simulator, failed with error " .. result,
        vim.log.levels.ERROR,
        { id = "Neoxcd", title = "Neoxcd" }
      )
    end
  end),
  open_in_xcode = nio.create(open_in_xcode),
}
