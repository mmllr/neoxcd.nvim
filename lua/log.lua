local M = {}

function M.log_line(...)
	local args = { ... }
	local str = ""
	for i, v in ipairs(args) do
		str = str .. tostring(v)
		if i < #args then
			str = str .. " "
		end
	end
	vim.cmd("echohl ModeMsg | echon '" .. str .. " ' | echohl None")
end

function M.message(...)
	local args = { ... }
	local str = ""
	for i, v in ipairs(args) do
		str = str .. tostring(v)
		if i < #args then
			str = str .. " "
		end
	end
	vim.cmd("echo '" .. str .. "'")
end

return M
