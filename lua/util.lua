local nio = require("nio")
local M = {}

--- Find files with a specific extension in a directory
---@param extension string
---@param directory string
---@return string[]
function M.find_files_with_extension(extension, directory)
	local pattern = directory .. "/*." .. extension
	local files = nio.fn.glob(pattern, false, true) -- Get a list of files
	return files
end

--- Concatenate two tables
---@param lhs table
---@param rhs table
---@return table
function M.concat(lhs, rhs)
	local result = {}
	for _, v in ipairs(lhs) do
		table.insert(result, v)
	end
	for _, v in ipairs(rhs) do
		table.insert(result, v)
	end
	return result
end

return M
