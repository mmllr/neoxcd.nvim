local neoxcd = require("neoxcd")
vim.api.nvim_create_user_command("NeoxcdSelectScheme", function()
	neoxcd.select_schemes()
end, {})

vim.api.nvim_create_user_command("NeoxcdSelectDestination", function()
	neoxcd.select_destination()
end, {})

vim.api.nvim_create_user_command("NeoxcdClean", function()
	neoxcd.clean()
end, {})

vim.api.nvim_create_user_command("NeoxcdBuild", function()
	neoxcd.build()
end, {})
