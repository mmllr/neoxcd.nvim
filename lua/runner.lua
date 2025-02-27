local M = {}
---@type table<TestEnumerationKind, string>
local symbols = {
  plan = "╮󰙨",
  target = "╮",
  test = "",
  class = "╮󰅩",
}

---@param node TestEnumeration
---@param prefix string
---@param is_last boolean
---@return string[]
local function format_tree(node, prefix, is_last)
  local lines = {}
  local symbol = symbols[node.kind]
  local connector = (is_last and "╰─" or "├─")
  local line = prefix .. connector .. symbol .. " " .. node.name
  table.insert(lines, line)

  if #node.children > 0 then
    for i, child in ipairs(node.children) do
      local new_prefix = prefix .. (is_last and "  " or "│ ")
      local child_lines = format_tree(child, new_prefix, i == #node.children)
      for _, child_line in ipairs(child_lines) do
        table.insert(lines, child_line)
      end
    end
  end

  return lines
end

---Formats a list of TestEnumeration objects for display in the runner list
---@param enumerations TestEnumeration[] List of test results
---@return string[] List of formatted results
function M.format(enumerations)
  local lines = {}

  for i, node in ipairs(enumerations) do
    local is_last = i == #enumerations
    local line = format_tree(node, "", is_last)
    for _, child_line in ipairs(line) do
      table.insert(lines, child_line)
    end
  end
  return lines
end

---Formats test results for display in the runner list
---@param results TestNode[]
---@return string[]
function M.format_results(results)
  local lines = {}
  return lines
end

return M
