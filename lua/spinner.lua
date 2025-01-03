local M = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_index = 1
local spinner_active = false

local function update_spinner()
	if not spinner_active then
		return
	end
	spinner_index = (spinner_index % #spinner_frames) + 1
	vim.api.nvim_command("redrawstatus")
	vim.defer_fn(update_spinner, 100)
end

function M.start()
	if spinner_active then
		return
	end
	spinner_active = true
	update_spinner()
end

function M.stop()
	spinner_active = false
	vim.api.nvim_command("redrawstatus")
end

function M.statusline()
	if spinner_active then
		return spinner_frames[spinner_index]
	else
		return ""
	end
end

return M
