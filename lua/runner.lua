local M = {}
---@type table<TestEnumerationKind, string>
local symbols = {
  plan = "╮󰙨",
  target = "╮",
  test = "",
  class = "╮󰅩",
  ["Unit test bundle"] = "╮",
  ["Test Suite"] = "╮󰅩",
  ["Test Case"] = "",
  ["Test Plan"] = "╮󰙨",
  ["Arguments"] = "",
}

local results = {
  ["Passed"] = " []",
  ["Failed"] = " []",
}

---@type string[]
local included_node_types = {
  "plan",
  "target",
  "test",
  "class",
  "Test Plan",
  "Test Case",
  "Test Suite",
  "Unit test bundle",
  "Arguments",
  "Repetition",
  "UI test bundle",
}

---Formats a test enumeration or a test node for display in the runner list
---@param item TestNode|TestEnumeration
---@param is_last boolean
---@return string
local function format_item(item, is_last)
  local key = item.kind or item.nodeType

  local symbol = symbols[key] or "???"
  local connector = (is_last and "╰─" or "├─")
  local result = item.result and results[item.result] or ""
  return connector .. symbol .. " " .. item.name .. result
end

---@param node TestEnumeration|TestNode
---@param prefix string
---@param is_last boolean
---@return string[]
local function format_node(node, prefix, is_last)
  local lines = {}
  table.insert(lines, prefix .. format_item(node, is_last))

  if node.children and #node.children > 0 then
    for i, child in ipairs(node.children) do
      local new_prefix = prefix .. (is_last and "  " or "│ ")
      if vim.tbl_contains(included_node_types, child.nodeType or child.kind) then
        local child_lines = format_node(child, new_prefix, i == #node.children)
        for _, child_line in ipairs(child_lines) do
          table.insert(lines, child_line)
        end
      end
    end
  end

  return lines
end

---Formats a list of TestEnumeration objects for display in the runner list
---@param items  TestEnumeration[]|TestNode[] List of test results
---@return string[] List of formatted results
function M.format(items)
  local lines = {}

  for i, node in ipairs(items) do
    local is_last = i == #items
    local line = format_node(node, "", is_last)
    for _, child_line in ipairs(line) do
      table.insert(lines, child_line)
    end
  end
  return lines
end

return M
