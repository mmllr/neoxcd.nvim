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
        nodeType = "Test Plan",
        result = "Passed",
        children = {
          {
            name = "Test target",
            nodeType = "Unit test bundle",
            result = "Passed",
            children = {
              {
                name = "Test",
                nodeType = "Test Suite",
                result = "Failed",
                children = {
                  {
                    duration = "1.234s",
                    name = "testSomething()",
                    nodeIdentifier = "Test/testSomething()",
                    nodeType = "Test Case",
                    result = "Passed",
                  },
                },
              },
            },
          },
        },
      },
    }

    assert.are.same({
      "╰─╮󰙨 Plan []",
      "  ╰─╮ Test target []",
      "    ╰─╮󰅩 Test []",
      "      ╰─ testSomething() []",
    }, sut.format(results))
  end)
end)
