vim.api.nvim_create_user_command("SelectXcodeScheme", function()
	require("neoxcd").select_schemes()
end, {})
