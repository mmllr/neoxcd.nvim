local M = {}

function M.show_window_with_content(content)
	-- Get the current Neovim window dimensions
	local width = vim.api.nvim_get_option_value("columns", {})
	local height = vim.api.nvim_get_option_value("lines", {})

	-- Calculate the window dimensions (70% width, 50% height)
	local win_width = math.floor(width * 0.7)
	local win_height = math.floor(height * 0.5)

	-- Calculate the window position (centered)
	local row = math.floor((height - win_height) / 2)
	local col = math.floor((width - win_width) / 2)

	-- Create a buffer for the window
	local buf = vim.api.nvim_create_buf(false, true)

	-- Set the buffer content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))

	-- Define the window options
	local opts = {
		style = "minimal",
		relative = "editor",
		width = win_width,
		height = win_height,
		row = row,
		col = col,
		border = "single",
	}

	-- Open the window
	vim.api.nvim_open_win(buf, true, opts)
end

return M
