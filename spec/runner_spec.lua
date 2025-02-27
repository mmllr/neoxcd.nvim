local assert = require("luassert")
local types = require("types")
local util = require("util")
local helpers = require("spec/helpers")

describe("Test runner", function()
  local sut = require("runner")
  local nio = require("nio")
  local it = nio.tests.it
  it("parses enumerated tests", function()
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
    }, sut.format(results))
  end)

  it("Parses test results", function()
    ---@type TestNode[]
    local results = {
      {
        name = "Plan",
        kind = "Test Plan",
        result = "Passed",
      },
    }

    -- assert.are.same({
    --   "╰─󰙨 Test Plan",
    -- }, sut.format_results(results))
  end)
end)
