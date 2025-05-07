local spinner = require("spinner")
local nio = require("nio")
local project = require("project")
local util = require("util")
local xcode = require("xcode")
local runner = require("runner")

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
    vim.notify("Failed to select scheme: " .. vim.inspect(selection), vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
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
---@param forTesting boolean If true, builds for testing
local function build(forTesting)
  local start_time = os.time()
  spinner.start(forTesting and "Build for testing..." or "Building project...")
  local code = xcode.build(forTesting or nil)
  nio.scheduler()
  spinner.stop()
  if code == 0 then
    local end_time = os.time()
    local msg = string.format("Build succeeded in %.2f seconds", os.difftime(end_time, start_time))
    vim.notify(msg, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
  else
    vim.notify("Build failed with code: " .. code, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
  end
  if project.current_project.quickfixes then
    vim.fn.setqflist(project.current_project.quickfixes, "r")
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

---A plugin for running xcode projects
---@class Neoxcd
---@field setup fun(options: table)
---@field clean fun()
---@field build fun(forTesting: boolean)
---@field select_schemes fun()
---@field select_destination fun()
---@field run fun()
---@field open_in_xcode fun()
---@field debug fun()
---@field stop fun()
---@field scan fun()
---@field test fun(test_identifier: string?)

---@type Neoxcd
return {
  setup = function(options)
    local group = vim.api.nvim_create_augroup("neoxcd.nvim", { clear = true })
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = group,
      pattern = "*.swift",
      callback = function(ev)
        if project.current_project.test_results then
          nio.run(function()
            project.update_test_results(ev.buf)
          end)
        end
      end,
    })
    nio.run(function()
      project.load()
    end)
  end,
  clean = nio.create(clean),
  build = nio.create(build, 1),
  select_schemes = nio.create(select_schemes),
  select_destination = nio.create(select_destination),
  run = nio.create(function()
    spinner.start("Starting " .. project.current_project.name .. "...")
    local result = project.run()
    spinner.stop()
    if result ~= 0 then
      vim.notify("Failed to run, failed with error " .. result, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
  end),
  open_in_xcode = nio.create(open_in_xcode),
  debug = nio.create(function()
    spinner.start("Debugging project...")
    local result = project.debug()
    spinner.stop()
    if result ~= 0 then
      vim.notify("Failed to debug project", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
  end),
  stop = nio.create(function()
    spinner.start("Stopping running target...")
    local result = project.stop()
    if result ~= 0 then
      vim.notify("Failed to stop running target, result: " .. result, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
    spinner.stop()
  end),
  scan = nio.create(function()
    spinner.start("Scanning for tests..")
    local result = project.discover_tests()
    nio.scheduler()
    spinner.stop()
    if result ~= 0 then
      vim.notify("Failed to scan for projects " .. result, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
      return
    end
    project.show_runner()
  end),
  test = nio.create(function(identifier)
    spinner.start(identifier and "Running " .. identifier or "Running tests...")
    local result = project.run_tests(identifier)
    nio.scheduler()
    spinner.stop()
    if result ~= 0 then
      vim.notify("Failed to run tests, result: " .. result, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
    end
  end),
}
