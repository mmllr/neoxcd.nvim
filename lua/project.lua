local M = {}

---@type Project|nil
M.current_project = nil

---@type Target|nil
M.current_target = nil

---Loads the project file in the current directory
function M.load()
  local files = vim.fs.find(function(name, path)
    return vim.endswith(name, ".xcworkspace") or vim.endswith(name, ".xcodeproj") or vim.endswith(name, "Package.swift")
  end, { limit = 3 })

  for _, file in ipairs(files) do
    if vim.endswith(file, "xcworkspace") then
      M.current_project = { path = file, type = "workspace", schemes = {} }
      return
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "xcodeproj") then
      M.current_project = { path = file, type = "project", schemes = {} }
      return
    end
  end
  for _, file in ipairs(files) do
    if vim.endswith(file, "Package.swift") then
      M.current_project = { path = file, type = "package", schemes = {} }
      return
    end
  end
  M.current_project = nil
end

---Returns the builld options for a project
---@param project Project
---@return string[]
function M.build_options_for_project(project)
  if project.type == "package" then
    return {}
  end
  return { "-" .. project.type, project.path }
end

--- Find the Xcode workspace or project file in the current directory
--- When no result is found, return empty table (Swift package projects do not have a workspace or project file)
---@return string[]|nil
function M.find_build_options()
  if M.current_project ~= nil then
    return M.build_options_for_project(M.current_project)
  end
  return nil
end

return M
