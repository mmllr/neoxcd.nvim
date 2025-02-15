local util = require("util")
local types = require("types")
local nio = require("nio")

local M = {}
---Result code enum
---@alias SimulatorResultCode integer
---| 0
---| -1
---| -2
---| -3
---| -4
---| 149

---@class SimulatorResultCodeConstants
---@field OK SimulatorResultCode
---@field SIM_CTL_ERROR SimulatorResultCode
---@field NO_XCODE SimulatorResultCode
---@field NO_SIMULATOR SimulatorResultCode
---@field INSTALL_FAILED SimulatorResultCode
---@field INVALID_DESTINATION SimulatorResultCode

---@type SimulatorResultCodeConstants
M.SimulatorResult = {
  OK = 0,
  NO_XCODE = -1,
  NO_SIMULATOR = -2,
  INSTALL_FAILED = -3,
  INVALID_DESTINATION = -4,
  SIM_CTL_ERROR = 149,
}

local cmd = nio.wrap(util.run_job, 3)

---Opens the Simulator app
---@async
---@return SimulatorResultCode
local function open_simulator_app()
  local result = cmd({ "xcode-select", "-p" })
  if result.code ~= M.SimulatorResult.OK or result.stdout == nil then
    return M.SimulatorResult.NO_XCODE
  end
  local simulator_path = string.gsub(result.stdout, "\n", "/Applications/Simulator.app")
  result = cmd({ "open", simulator_path })
  if result.code ~= M.SimulatorResult.OK then
    return M.SimulatorResult.NO_SIMULATOR
  end
  return result.code
end

---Boots the current simulator
---@async
---@param destination Destination
---@return SimulatorResultCode
function M.boot_simulator(destination)
  if destination.platform ~= types.Platform.IOS_SIMULATOR then
    return M.SimulatorResult.INVALID_DESTINATION
  end
  local result = cmd({ "xcrun", "simctl", "boot", destination.id }, nil)
  if result.code ~= M.SimulatorResult.OK then
    return result.code
  end

  return open_simulator_app()
end

---Installs the target on the simulator
---@async
---@param destination Destination
---@param app_path string
---@return SimulatorResultCode
function M.install_on_simulator(destination, app_path)
  local result = cmd({ "xcrun", "simctl", "install", destination.id, app_path }, nil)
  if result.code == M.SimulatorResult.SIM_CTL_ERROR then
    --- try to boot the simulator
    result = M.boot_simulator(destination)
    if result == M.SimulatorResult.OK then
      return M.install_on_simulator(destination, app_path)
    else
      return M.SimulatorResult.INSTALL_FAILED
    end
  end
  return result.code
end

return M
