local M = {}

---@type table<string, string>
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
  ["Repetition"] = "",
}

local result_icons = {
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

---The kind of a test diagnostic
---@alias DiagnosticKind "symbol"|"failure"

---A diagnostic message
---@class TestDiagnostic
---@field kind DiagnosticKind
---@field message string
---@field line number
---@field severity vim.diagnostic.Severity

---Gets all child nodes with a certain type
---@param node TestNode
---@param type TestNodeType
---@return TestNode[]
function M.children_with_type(node, type)
  local results = {}

  if node.nodeType == type then
    table.insert(results, node)
  end
  for _, child in ipairs(node.children or {}) do
    if child.nodeType == type then
      table.insert(results, child)
    end
    local child_results = M.children_with_type(child, type)
    for _, child_result in ipairs(child_results or {}) do
      table.insert(results, child_result)
    end
  end
  return results
end

---Formats a test enumeration or a test node for display in the runner list
---@param item TestNode|TestEnumeration
---@param is_last boolean
---@return string
local function format_item(item, is_last)
  local key = item.kind or item.nodeType

  local symbol = symbols[key] or "???"
  local connector = (is_last and "╰─" or "├─")
  local result = item.result and result_icons[item.result] or ""
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

---Extracts Test name and test method from a test node
---@param nodeIdentifier string
---@return string?, string?
function M.get_class_and_method(nodeIdentifier)
  return string.match(nodeIdentifier, "([^/]+)/(.+)")
end

---Finds a node with a prediate
---@param nodes TestNode[]
---@param predicate fun(node: TestNode): boolean
---@return TestNode|nil
local function find_node_with_predicate(nodes, predicate)
  for _, node in pairs(nodes) do
    if predicate(node) then
      return node
    end
    if node.children then
      local result = find_node_with_predicate(node.children, predicate)
      if result then
        return result
      end
    end
  end
  return nil
end

---Finds a node with a prediate
---@param nodes TestNode[]
---@param predicate fun(node: TestNode): boolean
---@return TestNode[]
local function find_nodes_with_predicate(nodes, predicate)
  local results = {}
  for _, node in pairs(nodes) do
    if predicate(node) then
      table.insert(results, node)
    end
    if node.children then
      local result = find_nodes_with_predicate(node.children, predicate)
      if result then
        for _, r in ipairs(result) do
          table.insert(results, r)
        end
      end
    end
  end
  return results
end

---Returns the severty for a test result
---@param result TestNodeResult
---@return vim.diagnostic.Severity
local function severity_for_result(result)
  if result == "Failed" then
    return vim.diagnostic.severity.ERROR
  end
  return vim.diagnostic.severity.INFO
end

---Returns all diagnposics for tests in a buffer
---@async
---@param buf integer
---@param nodes TestNode[]
---@return TestDiagnostic[]|nil
function M.diagnostics_for_tests_in_buffer(buf, nodes)
  local lsp = require("lsp")
  local document_symbols = lsp.document_symbol(buf)
  if not document_symbols then
    return nil
  end
  local suites = vim.tbl_filter(function(s)
    return s.kind == 5 or s.kind == 23
  end, document_symbols)
  local diagnostics = {}

  for _, suite in pairs(suites) do
    local node = find_node_with_predicate(nodes, function(n)
      return n.name == suite.name
    end)
    if node then
      table.insert(diagnostics, {
        kind = "symbol",
        message = node.duration or "",
        severity = severity_for_result(node.result),
        line = suite.range.start.line,
      })

      for _, test in ipairs(suite.children or {}) do
        if test.kind == 6 then
          local test_node = find_node_with_predicate(node.children or {}, function(n)
            return n.nodeIdentifier == suite.name .. "/" .. test.name
          end)
          if test_node then
            table.insert(diagnostics, {
              kind = "symbol",
              message = test_node.duration,
              severity = severity_for_result(test_node.result),
              line = test.range.start.line,
            })

            local failures = find_nodes_with_predicate(test_node.children or {}, function(n)
              return n.nodeType == "Failure Message"
            end)
            for _, failure in ipairs(failures) do
              local _, line, message = string.match(failure.name, "([^:]+):(%d+):%s*(.+)")
              table.insert(diagnostics, {
                kind = "failure",
                message = message,
                severity = vim.diagnostic.severity.ERROR,
                line = tonumber(line) - 1,
              })
            end
          end
        end
      end
    end
  end

  return diagnostics
end

return M
