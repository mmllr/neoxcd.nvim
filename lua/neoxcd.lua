local spinner = require("spinner")
local nio = require("nio")
local util = require("util")
local destination_mapping = {}
local ui = require("ui")

local M = {
	selected_scheme = nil,
}

---@class Destination
---@field platform string
---@field arch? string
---@field id string
---@field name string
---@field OS? string

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

--- Parse the output of `xcodebuild -list -json` into a table of schemes
---@param input string
---@param parent_key 'workspace'|'project' Decides what to do if a key is found in more than one map:
---@return string[]
local function parse_schemes(input, parent_key)
	local schemes = {}
	local data = vim.json.decode(input)
	if data and data[parent_key]["schemes"] then
		for _, scheme in ipairs(data[parent_key]["schemes"]) do
			table.insert(schemes, scheme)
		end
	end
	return schemes
end

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

local function show_destinations(scheme, opts)
	local output =
		run_external_cmd("xcodebuild", util.concat({ "-showdestinations", "-scheme", scheme, "-quiet" }, opts or {}))
	if output then
		return parse_destinations(output)
	else
		return nil
	end
end

M.setup = nio.create(function()
	local scheme = current_scheme(nio.fn.getcwd())
	if scheme then
		M.selected_scheme = scheme
	end
end)

--- Shows a list of schemes and updates the xcode-build-server config
M.select_schemes = nio.create(function()
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
		local key
		if vim.list_contains(opts, "-project") then
			key = "project"
		else
			key = "workspace"
		end
		schemes = parse_schemes(output, key)
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
		M.selected_scheme = selection
		nio.scheduler()
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
M.select_destination = nio.create(function()
	local scheme = M.selected_scheme or current_scheme(nio.fn.getcwd())
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
				format_item = format_destination,
			})
			destination_mapping[scheme] = selection
		else
			vim.notify("No destinations found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
		end
	else
		vim.notify("No scheme selected", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

--- Cleans the project
M.clean = nio.create(function()
	spinner.start("Cleaning project...")
	local scheme = M.select_scheme or current_scheme(nio.fn.getcwd())
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
		format_destination_for_build(destination_mapping[scheme]),
	})
	nio.scheduler()
	spinner.stop()
	if result ~= nil then
		vim.notify("Project cleaned", vim.log.levels.INFO, { id = "Neoxcd", title = "Neoxcd" })
	else
		vim.notify("Failed to clean project", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
	end
end)

M.build = nio.create(function()
	local opts = find_build_options()
	if opts == nil then
		vim.notify("No Xcode project or workspace found", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
		return
	end
	local scheme = M.selected_scheme or current_scheme(nio.fn.getcwd())
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
		format_destination_for_build(destination_mapping[scheme]),
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
end)

return M
