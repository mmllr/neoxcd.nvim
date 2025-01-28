local nio = require("nio")
local util = require("util")
local M = {}

---Update the Xcode build server config json
---@async
---@param scheme string
---param opts string[]|nil
function M.update_xcode_build_server(scheme, opts)
  local build = nio.process.run({
    cmd = "xcode-build-server",
    args = util.concat({ "config", "-scheme", scheme }, opts or {}),
  })
  if build == nil then
    return false
  end
  return build.result(true) == 0
end

return M
