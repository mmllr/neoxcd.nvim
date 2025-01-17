vim.api.nvim_create_user_command("NeoxcdSelectScheme", function()
  require("neoxcd").select_schemes()
end, {})

vim.api.nvim_create_user_command("NeoxcdSelectDestination", function()
  require("neoxcd").select_destination()
end, {})

vim.api.nvim_create_user_command("NeoxcdClean", function()
  require("neoxcd").clean()
end, {})

vim.api.nvim_create_user_command("NeoxcdBuild", function()
  require("neoxcd").build()
end, {})
