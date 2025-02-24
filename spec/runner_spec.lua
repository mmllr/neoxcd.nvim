local assert = require("luassert")
local types = require("types")
local util = require("util")
local helpers = require("spec/helpers")

describe("Test runner", function()
  local nio = require("nio")
  local it = nio.tests.it
  it("parses test results", function()
    ---@type TestEnumeration[]
    local results = {
      {
        name = "Test Plan",
        kind = "plan",
        disabled = false,
        children = {
          {
            name = "Test target",
            kind = "target",
            disabled = false,
            children = {
              {
                name = "Test",
                kind = "test",
                disabled = false,
                children = {},
              },
            },
          },
        },
      },
    }

    local runner = require("runner")
    assert.are.same({
      "󰙨 Test Plan",
      "╰╮ Test target",
      " ╰ Test",
    }, runner.format(results))
  end)
end)
