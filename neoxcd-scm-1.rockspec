rockspec_format = "3.0"
package = "neoxcd"
version = "scm-1"
source = {
	url = "git+https://github.com/mmllr/neoxcd.nvim",
}
dependencies = {
	"lua >= 5.1",
	"nvim-nio",
	"lrexlib-POSIX",
}
test_dependencies = {
	"nlua",
	"busted",
}
test = {
	type = "busted",
}
build = {
	type = "builtin",
	copy_directories = {
		-- Add runtimepath directories, like
		-- 'plugin', 'ftplugin', 'doc'
		-- here. DO NOT add 'lua' or 'lib'.
	},
}
