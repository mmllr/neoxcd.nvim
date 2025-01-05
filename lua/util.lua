local M = {}
local uv = vim.loop

--- Read a file
---@param filepath string
---@param callback fun(err: any|nil, data: any|nil)
function M.read_file(filepath, callback)
	uv.fs_open(filepath, "r", 438, function(err, fd)
		if err then
			callback(err, nil)
			return
		end
		uv.fs_fstat(fd, function(err, stat)
			if err then
				callback(err, nil)
				return
			end
			uv.fs_read(fd, stat.size, 0, function(err, data)
				if err then
					callback(err, nil)
					return
				end
				uv.fs_close(fd, function(err)
					if err then
						callback(err, nil)
						return
					end
					callback(nil, data)
				end)
			end)
		end)
	end)
end

--- Run an external command
---@param cmd string[]
---@param callback fun(result: vim.SystemCompleted)
function M.external_cmd(cmd, callback)
	vim.system(cmd, { text = true }, callback)
end

--- Find files with a specific extension in a directory
---@param extension string
---@param directory string
---@return string[]
function M.find_files_with_extension(extension, directory)
	local pattern = directory .. "/*." .. extension
	local files = vim.fn.glob(pattern, false, true) -- Get a list of files
	return files
end

return M
