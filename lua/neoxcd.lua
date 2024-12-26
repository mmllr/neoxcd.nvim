local M = {}

--- Load schemes from a xcode poject
---@return string[]
local load_schemes = function()
	local schemes = {}
	local result = vim.system({ "xcodebuild", "-list", "-json" }, { text = true }):wait()
	if result.code == 0 then
		local data = vim.fn.json_decode(result.stdout)
		if data and data["project"]["schemes"] then
			for _, scheme in ipairs(data["project"]["schemes"]) do
				table.insert(schemes, scheme)
			end
		end
	end
	return schemes
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

M.setup = function() end

M.select_schemes = function()
	local schemes = load_schemes()
	vim.ui.select(schemes, {
		prompt = "Select a scheme",
	}, function(selected)
		if selected then
			local projects = find_files_with_extension("xcodeproj", vim.fn.getcwd())
			local first_project = projects[1]
			if first_project then
				local result = vim.system(
					{ "xcode-build-server", "config", "-scheme", selected, "-project", first_project },
					{ text = true }
				):wait()
				if result.code == 0 then
					vim.print("Selected scheme " .. selected)
				else
					vim.print("Failed to run xcode-build-server " .. result.stderr)
				end
			end
		end
	end)
end

return M
