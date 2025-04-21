local assert = require("luassert")

describe("Test runner", function()
  local sut = require("runner")
  local nio = require("nio")
  local it = nio.tests.it

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
                  {
                    duration = "0.815s",
                    name = "testAnotherThing()",
                    nodeIdentifier = "Test/testAnotherThing()",
                    result = "Passed",
                    nodeType = "Test Case",
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
              range = { start = { line = 30, character = 0 }, ["end"] = { line = 40, character = 5 } },
            },
            {
              name = "testAnotherThing()",
              kind = 6,
              range = { start = { line = 50, character = 0 }, ["end"] = { line = 60, character = 5 } },
            },
          },
        },
      },
    }

    local function stub_lsp()
      vim.lsp.get_clients = function(_)
        return {
          { bufnr = 42, name = "sourcekit", id = 1, flags = {} },
        }
      end
      vim.uri_from_bufnr = function(bufnr)
        assert(bufnr == 42)
        return "file:///path/to/file"
      end
      vim.lsp.buf_request_all = function(buf, method, _, callback)
        assert(method == "textDocument/documentSymbol")
        callback({
          [1] = { result = stubbed_symbols[buf] },
        }, { client_id = 1, method = method, bufnr = 42 })
      end
    end

    stub_lsp()
    local diagnostics = sut.diagnostics_for_tests_in_buffer(42, results)

    ---@type TestDiagnostic[]
    local expected = {
      {
        kind = "symbol",
        message = "42s",
        severity = vim.diagnostic.severity.ERROR,
        line = 0,
      },
      {
        kind = "symbol",
        message = "1.234s",
        severity = vim.diagnostic.severity.ERROR,
        line = 30,
      },
      {
        kind = "failure",
        message = "Issue recorded: A state change does not match expectation: …\n\n      State(\n        _selection: .someState,\n\n(Expected: −, Actual: +)",
        severity = vim.diagnostic.severity.ERROR,
        line = 40,
      },
      {
        kind = "symbol",
        message = "0.815s",
        severity = vim.diagnostic.severity.INFO,
        line = 50,
      },
    }
    assert.are.same(expected, diagnostics)
  end)

  it("Parses ripgrep output", function()
    local output = [[
project-kit/Tests/FeatureTests/FeatureTest.swift:10:    struct TheTest {
project-kit/Tests/FeatureTests/FeatureTest.swift:16:    @Test func testNavigation() async throws {"
]]
    local last_line = output:match("([^\n]*)\n?$")
    local file_path, line_number = last_line:match("^(.-):(%d+):")

    assert.are.same("project-kit/Tests/FeatureTests/FeatureTest.swift", file_path)
    assert.are.same(16, tonumber(line_number))
  end)
end)
