local spinner = require("spinner")
local a = require("async")
local util = require("util")
local destination_mapping = {}

local M = {}

---@class Destination
---@field platform string
---@field arch? string
---@field id string
---@field name string
---@field OS? string

--- Returns the output or nil if the command failed
---@param result vim.SystemCompleted
---@return string|nil
local function output_or_nil(result)
	if result.code == 0 then
		return result.stdout
	else
		return nil
	end
end

--- Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
local function parse_destinations(text)
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

--- Format a destination for display in the UI
---@param destination Destination
---@return string
local function format_destination(destination)
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

--- Format a destination for use in a build command
---@param destination Destination
local function format_destination_for_build(destination)
	local keys = { "platform", "arch", "id" }
	local parts = {}
	for k, v in pairs(destination) do
		if vim.tbl_contains(keys, k) then
			table.insert(parts, k .. "=" .. v)
		end
	end
	return table.concat(parts, ",")
end

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
	util.external_cmd({ "xcodebuild", "-list", "-json" }, function(result)
		callback(output_or_nil(result))
	end)
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

local function show_ui(schemes, opts, callback)
	vim.ui.select(schemes, opts, callback)
end

local show_ui_async = a.wrap(show_ui)

local function show_destinations(scheme, project, callback)
	util.external_cmd(
		{ "xcodebuild", "-showdestinations", "-scheme", scheme, "-project", project, "-quiet" },
		function(result)
			local output = output_or_nil(result)
			if output then
				callback(parse_destinations(output))
			else
				callback(nil)
			end
		end
	)
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
	local selection = a.wait(show_ui_async(schemes, {
		prompt = "Select a scheme",
	}))
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
		if #destinations > 0 and destinations then
			a.wait(main_loop)
			local selection = a.wait(show_ui_async(destinations, {
				prompt = "Select a destination",
				format_item = format_destination,
			}))
			vim.notify(format_destination(selection), vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
			destination_mapping[scheme] = selection
		else
			vim.notify("No destinations found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
		end
	else
		vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

--- Cleans the project
M.clean = a.sync(function()
	spinner.start("Cleaning project...")
	local project = find_xcode_project("xcodeproj")
	local result = a.wait(a.wrap(util.external_cmd)({ "xcodebuild", "clean", "-project", project }))
	a.wait(main_loop)
	spinner.stop()
	if result.code == 0 then
		vim.notify("Project cleaned", vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
	else
		vim.notify("Failed to clean project", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

M.build = a.sync(function()
	local project = find_xcode_project("xcodeproj")
	local scheme = a.wait(current_scheme_async(vim.fn.getcwd()))
	a.wait(main_loop)
	if destination_mapping[scheme] == nil then
		vim.notify(
			"No destination selected, use NeoxcdSelectDestination to choose a destination",
			vim.log.levels.ERROR,
			{ id = "Neoxcd", title = "Neoxcd" }
		)
		return
	end
	spinner.start("Building " .. scheme .. "...")
	--- TODO: query available configurations instead of hardcoding "Debug"
	local cmd = {
		"xcodebuild",
		"build",
		"-scheme",
		scheme,
		"-destination",
		format_destination_for_build(destination_mapping[scheme]),
		"-configuration",
		"Debug",
		"-project",
		project,
	}
	vim.notify(table.concat(cmd, " "), vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
	local result = a.wait(a.wrap(util.external_cmd)(cmd))
	a.wait(main_loop)
	spinner.stop()
	if result.code == 0 then
		vim.notify("Build succeeded", vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
	else
		vim.notify("Build failed" .. result.stderr, vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

return M
