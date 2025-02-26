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
              {
                name = "Test 2",
                kind = "test",
                disabled = false,
                children = {},
              },
              {
                name = "TestCase1",
                kind = "class",
                disabled = false,
                children = {
                  {
                    name = "Test1",
                    kind = "test",
                    disabled = false,
                    children = {},
                  },
                  {
                    name = "Test2",
                    kind = "test",
                    disabled = false,
                    children = {},
                  },
                },
              },
              {
                name = "TestCase2",
                kind = "class",
                disabled = false,
                children = {
                  {
                    name = "Test1",
                    kind = "test",
                    disabled = false,
                    children = {},
                  },
                  {
                    name = "Test2",
                    kind = "test",
                    disabled = false,
                    children = {},
                  },
                },
              },
            },
          },
        },
      },
    }
    -- │╰╮
    local runner = require("runner")
    assert.are.same({
      "╰─╮󰙨 Test Plan",
      "  ╰─╮ Test target",
      "    ├─ Test",
      "    ├─ Test 2",
      "    ├─╮󰅩 TestCase1",
      "    │ ├─ Test1",
      "    │ ╰─ Test2",
      "    ╰─╮󰅩 TestCase2",
      "      ├─ Test1",
      "      ╰─ Test2",
    }, runner.format(results))
  end)
end)
