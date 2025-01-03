local spinner = require("spinner")
local a = require("async")
local M = {}

local main_loop = function(f)
	vim.schedule(f)
end

local external_cmd = function(cmd, callback)
	vim.system(cmd, { text = true }, function(result)
		if result.code ~= 0 then
			vim.notify("Failed to run xcode-build-server", vim.log.levels.ERROR, { id = "Neoxcd", title = "Neoxcd" })
			callback(nil)
		else
			callback(result.stdout)
		end
	end)
end

--- Find files with a specific extension in a directory
---@param extension string
---@param directory string
---@return string[]
local function find_files_with_extension(extension, directory)
	local pattern = directory .. "/*." .. extension
	local files = vim.fn.glob(pattern, false, true) -- Get a list of files
	return files
end

local parse_schemes = function(input)
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
	external_cmd({ "xcodebuild", "-list", "-json" }, callback)
end

local load_schemes_async = a.wrap(load_schemes)

--- Find the xcode project in the current directory
---@param extension string
local find_xcode_project = function(extension)
	local projects = find_files_with_extension(extension, vim.fn.getcwd())
	return projects[1]
end

local update_xcode_build_config = function(scheme, project, callback)
	external_cmd({ "xcode-build-server", "config", "-scheme", scheme, "-project", project }, callback)
end

local update_xcode_build_config_async = a.wrap(update_xcode_build_config)

local show_ui = function(schemes, callback)
	vim.ui.select(schemes, {
		prompt = "Select a scheme",
	}, callback)
end

local show_ui_async = a.wrap(show_ui)

M.setup = function() end

M.select_schemes = function()
	spinner.start("Loading schemes...")
	a.sync(function()
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
	end)()
end

return M
