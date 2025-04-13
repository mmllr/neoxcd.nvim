local assert = require("luassert")

describe("Util", function()
  local util = require("util")

  it("Concatenates two tables", function()
    local lhs = { "a", "b", "c" }
    local rhs = { "d", "e", "f" }
    local result = util.concat(lhs, rhs)

    assert.are.same({ "a", "b", "c", "d", "e", "f" }, result)
  end)

  it("Removes nil values from a table", function()
    local array = {}
    table.insert(array, 1)
    table.insert(array, 2)
    table.insert(array, nil)
    table.insert(array, 3)
    table.insert(array, nil)
    table.insert(array, 4)
    local result = util.lst_remove_nil_values(array)

    assert.are.same({ 1, 2, 3, 4 }, result)
  end)

  it("Concatenates multiple tables", function()
    local t1 = { "a", "b" }
    local t2 = { "c", "d" }
    local t3 = { "e", "f" }
    local result = util.concat(t1, t2, t3)

    assert.are.same({ "a", "b", "c", "d", "e", "f" }, result)
  end)
end)
