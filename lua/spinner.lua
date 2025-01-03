local M = {}

local log = require("log")
local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1
local spinner_active = false
local message = ""

local function update_spinner()
	if not spinner_active then
		vim.cmd("echo ''") -- Clear the command line
		return
	end
	spinner_index = (spinner_index % #spinner_frames) + 1
	log.log_line(spinner_frames[spinner_index], message)
	vim.defer_fn(update_spinner, 100)
end

--- Start the spinner
---@param text string?
function M.start(text)
	message = text or ""
	if spinner_active then
		return
	end
	spinner_active = true
	update_spinner()
end

function M.stop()
	spinner_active = false
	log.message("")
end

function M.statusline()
	if spinner_active then
		return spinner_frames[spinner_index]
	else
		return ""
	end
end

return M
