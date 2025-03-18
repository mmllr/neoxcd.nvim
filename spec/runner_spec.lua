local assert = require("luassert")
local types = require("types")
local util = require("util")
local helpers = require("spec/helpers")

describe("Test runner", function()
  local sut = require("runner")
  local nio = require("nio")
  local it = nio.tests.it
  local lsp = require("lsp")

  it("Parses test node identifiers", function()
    local class_name, method_name = sut.get_class_and_method("Test/testSomething")

    assert.equals("Test", class_name)
    assert.equals("testSomething", method_name)

    class_name, method_name = sut.get_class_and_method("Test/testSomething(value:)")
    assert.equals("Test", class_name)
    assert.equals("testSomething(value:)", method_name)
  end)

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

  it("Parses failure messages with new-lines", function()
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
                duration = "42s",
                children = {
                  {
                    duration = "1.234s",
                    name = "testSomething()",
                    nodeIdentifier = "Test/testSomething()",
                    nodeType = "Test Case",
                    result = "Failed",
                    children = {
                      {
                        name = "TestSuite.swift:41: Issue recorded: A state change does not match expectation: …\n\n      State(\n        _selection: .someState,\n\n(Expected: −, Actual: +)",
                        nodeType = "Failure Message",
                        result = "Failed",
                      },
                    },
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
      "      ╰─ testSomething() []",
    }, sut.format(results))
  end)

  it("updates diagnostics", function()
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
                duration = "42s",
                children = {
                  {
                    duration = "1.234s",
                    name = "testSomething()",
                    nodeIdentifier = "Test/testSomething()",
                    nodeType = "Test Case",
                    result = "Failed",
                    children = {
                      {
                        name = "TestSuite.swift:41: Issue recorded: A state change does not match expectation: …\n\n      State(\n        _selection: .someState,\n\n(Expected: −, Actual: +)",
                        nodeType = "Failure Message",
                        result = "Failed",
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }
    ---@type table<integer, lsp.types.Symbol[]>
    local stubbed_symbols = {
      [42] = {
        {
          name = "Test",
          kind = 5,
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 3, character = 5 } },
          children = {
            {
              name = "testSomething()",
              kind = 6,
              range = { start = { line = 40, character = 0 }, ["end"] = { line = 40, character = 5 } },
            },
          },
        },
      },
    }

    ---@diagnostic disable-next-line: duplicate-set-field
    lsp.document_symbol = function(buf)
      return stubbed_symbols[buf]
    end

    local diagnostics = sut.diagnostics_for_tests_in_buffer(42, results)

    assert.are.same({
      ---@type TestDiagnostic
      {
        message = "42s",
        severity = vim.diagnostic.severity.ERROR,
        line = 0,
      },
      {
        message = "1.234s",
        severity = vim.diagnostic.severity.ERROR,
        line = 40,
      },
    }, diagnostics)
  end)
end)
