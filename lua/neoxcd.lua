local spinner = require("spinner")
local a = require("async")
local util = require("util")

local M = {}

local main_loop = function(f)
	vim.schedule(f)
end

---@param directory string
---@param callback fun(scheme: string|nil)
local function current_scheme(directory, callback)
	util.read_file(directory .. "/buildServer.json", function(err, data)
		if err then
			callback(nil)
			return
		end
		local decoded = vim.json.decode(data)
		if decoded and decoded["scheme"] then
			callback(decoded["scheme"])
		else
			callback(nil)
		end
	end)
end

local current_scheme_async = a.wrap(current_scheme)

local function parse_schemes(input)
	local schemes = {}
	local data = vim.json.decode(input)
	if data and data["project"]["schemes"] then
		for _, scheme in ipairs(data["project"]["schemes"]) do
			table.insert(schemes, scheme)
		end
	end
	return schemes
end

local load_schemes = function(callback)
	util.external_cmd({ "xcodebuild", "-list", "-json" }, callback)
end

local load_schemes_async = a.wrap(load_schemes)

--- Find the xcode project in the current directory
---@param extension string
local function find_xcode_project(extension)
	local projects = util.find_files_with_extension(extension, vim.fn.getcwd())
	return projects[1]
end

local function update_xcode_build_config(scheme, project, callback)
	util.external_cmd({ "xcode-build-server", "config", "-scheme", scheme, "-project", project }, callback)
end

local update_xcode_build_config_async = a.wrap(update_xcode_build_config)

local function show_ui(schemes, callback)
	vim.ui.select(schemes, {
		prompt = "Select a scheme",
	}, callback)
end

local show_ui_async = a.wrap(show_ui)

local function show_destinations(scheme, project, callback)
	util.external_cmd({ "xcodebuild", "-showdestinations", "-scheme", scheme, "-project", project, "-quiet" }, callback)
end

local show_destinations_async = a.wrap(show_destinations)

function M.setup() end

--- Shows a list of schemes and updates the xcode-build-server config
M.select_schemes = a.sync(function()
	spinner.start("Loading schemes...")
	local output = a.wait(load_schemes_async())
	a.wait(main_loop)
	spinner.stop()
	local schemes = {}
	if output == nil then
		vim.notify("No schemes found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
		return
	else
		schemes = parse_schemes(output)
	end
	local selection = a.wait(show_ui_async(schemes))
	if selection then
		spinner.start("Updating xcode-build-server config...")
		local project = find_xcode_project("xcodeproj")
		local success = a.wait(update_xcode_build_config_async(selection, project))
		a.wait(main_loop)
		spinner.stop()
		if success then
			vim.notify("Selected scheme: " .. selection, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
		else
			vim.notify(
				"Failed to select scheme: " .. selection,
				vim.log.levels.ERROR,
				{ id = "Neoxcd", title = "Neoxcd" }
			)
		end
	end
end)

--- Selects a destination for the current scheme
M.select_destination = a.sync(function()
	local scheme = a.wait(current_scheme_async(vim.fn.getcwd()))
	a.wait(main_loop)
	if scheme then
		spinner.start("Loading destinations for scheme: " .. scheme .. "...")
		local project = find_xcode_project("xcodeproj")
		local destinations = a.wait(show_destinations_async(scheme, project))
		spinner.stop()
		if destinations then
			vim.notify(destinations, vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
		end
	else
		vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

return M
