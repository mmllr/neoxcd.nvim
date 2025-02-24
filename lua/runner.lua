local M = {}

local kind_symbols = {
  plan = "󰙨",
  target = "",
  test = "",
}

---@param lines string[]
---@param tests TestEnumeration[]
---@param indent number
local function insert_test_results(lines, tests, indent)
  for idx, test in ipairs(tests) do
    local symbol = string.rep(" ", indent - 1)
    if indent > 0 then
      if idx == 1 then
        symbol = symbol .. "╰"
      end
      if #test.children > 0 then
        symbol = symbol .. "╮"
      end
    end
    local line = string.format("%s%s %s", symbol, kind_symbols[test.kind], test.name)
    table.insert(lines, line)
    if #test.children > 0 then
      insert_test_results(lines, test.children, indent + 1)
    end
  end
end

---Formats a list of TestEnumeration objects for display in the runner list
---@param results TestEnumeration[] List of test results
---@return string[] List of formatted results
function M.format(results)
  local lines = {}
  insert_test_results(lines, results, 0)
  return lines
end

return M
