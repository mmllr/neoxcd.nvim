local neoxcd = require("neoxcd")
vim.api.nvim_create_user_command("NeoxcdSelectScheme", function()
	neoxcd.select_schemes()
end, {})
