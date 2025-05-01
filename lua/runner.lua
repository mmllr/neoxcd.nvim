local NuiTree = require("nui.tree")
local Split = require("nui.split")
local NuiLine = require("nui.line")
local util = require("util")
local nio = require("nio")

local M = {}

---@type NuiTree?
local tree = nil

---@type table<string, string>
local symbols = {
  ["Unit test bundle"] = "╮",
  ["Test Suite"] = "╮󰅩",
  ["Test Case"] = "",
  ["Test Plan"] = "╮󰙨",
  ["Arguments"] = "",
  ["Repetition"] = "",
}

local result_icons = {
  ["Passed"] = " []",
  ["Failed"] = " []",
}

---@type TestNodeType[]
local included_node_types = {
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
---@field result TestNodeResult

---Returns the icon for a test node result
---@param result? TestNodeResult
---@return string
function M.icon_for_result(result)
  ---@type table<TestNodeResult, string>
  local icons = {
    ["Passed"] = "",
    ["Failed"] = "",
    ["Skipped"] = "⤼",
    ["Expected Failure"] = "⚒︎",
    ["unknown"] = "",
  }
  return icons[result or "unknown"]
end

---Returns the highlight for a test node result
---@param result? TestNodeResult
---@return string
function M.highlight_for_result(result)
  ---@type table<TestNodeResult, string>
  local highlights = {
    ["Passed"] = "DiagnosticOk",
    ["Failed"] = "DiagnosticError",
    ["Skipped"] = "DiagnosticInfo",
    ["Expected Failure"] = "DiagnosticWarn",
    ["unknown"] = "DiagnosticInfo",
  }
  return highlights[result or "unknown"]
end

---Returns the highlight for a test node result
---@param result? TestNodeResult
---@return string
function M.virtual_highlight_for_result(result)
  ---@type table<TestNodeResult, string>
  local highlights = {
    ["Passed"] = "DiagnosticOk",
    ["Failed"] = "DiagnosticError",
    ["Skipped"] = "DiagnosticInfo",
    ["Expected Failure"] = "DiagnosticWarn",
    ["unknown"] = "DiagnosticInfo",
  }
  return highlights[result or "unknown"]
end

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

---Formats a test node for display in the runner list
---@param item TestNode
---@param is_last boolean
---@return string
local function format_item(item, is_last)
  local key = item.nodeType

  local symbol = symbols[key] or "???"
  local connector = (is_last and "╰─" or "├─")
  local result = item.result and result_icons[item.result] or ""
  return connector .. symbol .. " " .. item.name .. result
end

---@param node TestNode
---@param prefix string
---@param is_last boolean
---@return string[]
local function format_node(node, prefix, is_last)
  local lines = {}
  table.insert(lines, prefix .. format_item(node, is_last))

  if node.children and #node.children > 0 then
    for i, child in ipairs(node.children) do
      local new_prefix = prefix .. (is_last and "  " or "│ ")
      if vim.tbl_contains(included_node_types, child.nodeType) then
        local child_lines = format_node(child, new_prefix, i == #node.children)
        for _, child_line in ipairs(child_lines) do
          table.insert(lines, child_line)
        end
      end
    end
  end

  return lines
end

---Formats a list of TestNode objects for display in the runner list
---@param items  TestNode[] List of test results
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
  ---@type TestDiagnostic[]
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
        result = node.result or "unknown",
      })

      for _, test in ipairs(suite.children or {}) do
        if test.kind == 6 then
          local test_node = find_node_with_predicate(node.children or {}, function(n)
            return n.nodeIdentifier == suite.name .. "/" .. test.name
          end)
          if test_node then
            table.insert(diagnostics, {
              kind = "symbol",
              message = test_node.duration or "",
              severity = severity_for_result(test_node.result),
              line = test.range.start.line,
              result = test_node.result or "unknown",
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
                result = test_node.result or "unknown",
              })
            end
          end
        end
      end
    end
  end

  return diagnostics
end

local split = Split({
  relative = "editor",
  size = "20%",
  position = "right",
})

---@param node TestNode
---@return boolean
local function is_in_tree(node)
  if node.nodeType and node.nodeType == "Failure Message" then
    return false
  else
    return true
  end
end

---@param node TestNode
---@return string
local function id_for_node(node)
  if node.nodeType and node.nodeType == "Repetition" then
    return node.name
  else
    return node.nodeIdentifier or node.name
  end
end

---Creates a NuiTeee.Node from a TestNode
---@param item TestNode
---@param parentID string
---@return NuiTree.Node|nil
local function create_tree_node(item, parentID)
  local id = parentID .. "/" .. id_for_node(item)

  local result = {}
  for _, child in ipairs(item.children or {}) do
    if is_in_tree(child) then
      local c = create_tree_node(child, id)
      table.insert(result, c)
    end
  end
  return NuiTree.Node({
    test_node = item,
    id = item.nodeIdentifierURL or id,
    text = item.name,
  }, item.children and result or nil)
end

---Tansforms a list of TestNodes into a list of NuiTree tables
---@param nodes TestNode[]
---@return NuiTree.Node[]
local function create_tree(nodes)
  local result = {}
  for _, node in ipairs(nodes) do
    table.insert(result, create_tree_node(node, ""))
  end
  return result
end

---@async
---@param symbol string
---@param parent string|nil
local function find_symbol(symbol, parent)
  local test_name = symbol:match("^[^(]+") or symbol
  local cmd = {
    "rg",
    "-t",
    "swift",
    "--multiline-dotall",
    "--line-number",
  }
  if parent ~= nil then
    table.insert(cmd, "-U")
    table.insert(cmd, parent .. ".*" .. test_name)
  else
    table.insert(cmd, "func\\s+" .. test_name)
  end
  local ripgrep = nio.wrap(util.run_job, 3)
  local result = ripgrep(cmd, nil)

  if result.code == 0 and result.stdout then
    local last_line = result.stdout:match("([^\n]*)\n?$")
    local file_path, line_number = last_line:match("^(.-):(%d+):")
    if file_path and line_number then
      -- Open the file at the specified line number
      nio.api.nvim_command("wincmd h | e +" .. line_number .. " " .. file_path)
    else
      print("No match found")
    end
  end
end

---Finds a parent node in a nui tree with a specific test node type
---@param node NuiTree.Node
---@param type TestNodeType
---@param tree NuiTree
---@return NuiTree.Node|nil
local function find_parent_test_node(node, type, tree)
  if node.test_node and node.test_node.nodeType == type then
    return node
  else
    local parent_id = node:get_parent_id()
    if parent_id == nil then
      return nil
    end
    local parent = tree:get_node(parent_id)
    if parent == nil then
      return nil
    end
    return find_parent_test_node(parent, type, tree)
  end
end

---Finds a parent node in a nui tree with a specific test node type
---@param node NuiTree.Node
---@param tree NuiTree
---@return string|nil
---@return string|nil
local function find_node_symbol_names(node, tree)
  if node.test_node and node.test_node.nodeType == "Test Case" then
    local parent = find_parent_test_node(node, "Test Suite", tree)
    return node.test_node.name, parent and parent.test_node and parent.test_node.name or nil
  else
    local parent = find_parent_test_node(node, "Test Case", tree)
    if parent ~= nil then
      return find_node_symbol_names(parent, tree)
    end
    return nil, nil
  end
end

---Configures the split window
---@param tree NuiTree
local function configure_split(tree)
  split:map("n", "q", function()
    split:unmount()
  end, { noremap = true })
  local map_options = { noremap = true, nowait = true }

  split:map(
    "n",
    "<CR>",
    nio.create(function()
      local node = tree:get_node()
      if node then
        local test, parent = find_node_symbol_names(node, tree)
        if test then
          find_symbol(test, parent)
        end
      end
    end),
    { noremap = true, nowait = false }
  )

  split:map(
    "n",
    "r",
    nio.create(function()
      local node = tree:get_node()
      if node and node.test_node and node.test_node.nodeIdentifier then
        local bundle_node = find_parent_test_node(node, "Unit test bundle", tree)
        if bundle_node and bundle_node.test_node then
          require("neoxcd").test(bundle_node.test_node.name .. "/" .. node.test_node.nodeIdentifier)
        end
      end
    end),
    { noremap = true, nowait = false }
  )

  -- collapse current node
  split:map("n", "h", function()
    local node = tree:get_node()

    if node and node:collapse() then
      tree:render()
    end
  end, map_options)

  -- collapse all nodes
  split:map("n", "H", function()
    local updated = false

    for _, node in pairs(tree.nodes.by_id) do
      updated = node:collapse() or updated
    end

    if updated then
      tree:render()
    end
  end, map_options)

  -- expand current node
  split:map("n", "l", function()
    local node = tree:get_node()

    if node and node:expand() then
      tree:render()
    end
  end, map_options)

  -- expand all nodes
  split:map("n", "L", function()
    local updated = false

    for _, node in pairs(tree.nodes.by_id) do
      updated = node:expand() or updated
    end

    if updated then
      tree:render()
    end
  end, map_options)
end

---Formats a test node for display in the runner list
---@param item TestNode
---@param line NuiLine
local function format_item_nui(item, line)
  line:append("[")
  line:append(M.icon_for_result(item.result), M.highlight_for_result(item.result))
  line:append("] " .. item.name)
  if item.duration then
    line:append(" (")
    line:append(item.duration, "DiagnosticInfo")
    line:append(")")
  end
end

---Displays the runner window
---@param results TestNode[]|nil
function M.show(results)
  local nodes
  if results == nil or #results == 0 then
    nodes = {
      NuiTree.Node({
        text = "No tests found",
        id = "no-tests",
      }),
    }
  else
    nodes = create_tree(results)
  end
  split:show()

  tree = NuiTree({
    bufnr = split.bufnr,
    nodes = nodes,
    prepare_node = function(node)
      local line = NuiLine()
      line:append(string.rep("  ", node:get_depth() - 1))

      if node:has_children() then
        line:append(node:is_expanded() and " " or " ", "SpecialChar")
      else
        line:append("  ")
      end

      if node.test_node then
        format_item_nui(node.test_node, line)
      else
        line:append(node.text)
      end
      return line
    end,
  })

  configure_split(tree)

  tree:render()
end

---@param existing TestNode[]
---@param new TestNode[]
---@return TestNode[]
function M.merge_nodes(existing, new)
  -- Create a lookup table for updated nodes by their name
  local updated_lookup = {}

  for _, node in ipairs(new) do
    updated_lookup[node.name] = node
  end

  ---@param existing_node TestNode
  ---@param updated? TestNode
  ---@return TestNode
  local function deep_merge(existing_node, updated)
    local merged = {}

    -- Copy all from existing node
    for k, v in pairs(existing_node) do
      merged[k] = v
    end

    -- Override result based on presence in updated
    if updated then
      merged.result = updated.result
    else
      merged.result = "unknown"
    end

    -- Merge children
    local children1 = existing_node.children or {}
    local children2 = updated and updated.children or {}
    merged.children = M.merge_nodes(children1, children2)

    return merged
  end

  local mergedList = {}

  for _, node in ipairs(existing or {}) do
    table.insert(mergedList, deep_merge(node, updated_lookup[node.name]))
    updated_lookup[node.name] = nil
  end

  for _, node in pairs(updated_lookup) do
    table.insert(mergedList, node)
  end

  return mergedList
end

return M
