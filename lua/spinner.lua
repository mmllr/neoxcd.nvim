local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1
local spinner_active = false
local message = ""

local function update_spinner()
	if not spinner_active then
		return
	end
	spinner_index = (spinner_index % #spinner_frames) + 1
	local msg = spinner_frames[spinner_index] .. " " .. message
	vim.notify(msg, vim.log.levels.INFO, { title = "Neoxcd", id = "Neoxcd" })
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
	vim.notify("Done", vim.log.levels.INFO, { title = "Neoxcd", id = "Neoxcd" })
end

function M.statusline()
	if spinner_active then
		return spinner_frames[spinner_index]
	else
		return ""
	end
end

return M
