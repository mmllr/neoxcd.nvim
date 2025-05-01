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
    ---@type TestNode[]
    local results = {
      {
        name = "Test Plan",
        nodeType = "Test Plan",
        children = {
          {
            name = "Test target",
            nodeType = "Unit test bundle",
            disabled = false,
            children = {
              {
                name = "Test",
                nodeType = "Test Case",
                disabled = false,
                children = {},
              },
              {
                name = "Test 2",
                nodeType = "Test Case",
                disabled = false,
                children = {},
              },
              {
                name = "TestCase1",
                nodeType = "Test Suite",
                disabled = false,
                children = {
                  {
                    name = "Test1",
                    nodeType = "Test Case",
                    disabled = false,
                    children = {},
                  },
                  {
                    name = "Test2",
                    nodeType = "Test Case",
                    disabled = false,
                    children = {},
                  },
                },
              },
              {
                name = "TestCase2",
                nodeType = "Test Suite",
                disabled = false,
                children = {
                  {
                    name = "Test1",
                    nodeType = "Test Case",
                    disabled = false,
                    children = {},
                  },
                  {
                    name = "Test2",
                    nodeType = "Test Case",
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
      "    ╰─╮󰅩 Test []",
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
      "    ╰─╮󰅩 Test []",
      "      ╰─ testSomething() []",
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
        result = "Failed",
      },
      {
        kind = "symbol",
        message = "1.234s",
        severity = vim.diagnostic.severity.ERROR,
        line = 30,
        result = "Failed",
      },
      {
        kind = "failure",
        message = "Issue recorded: A state change does not match expectation: …\n\n      State(\n        _selection: .someState,\n\n(Expected: −, Actual: +)",
        severity = vim.diagnostic.severity.ERROR,
        line = 40,
        result = "Failed",
      },
      {
        kind = "symbol",
        message = "0.815s",
        severity = vim.diagnostic.severity.INFO,
        line = 50,
        result = "Passed",
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

  describe("Merging nodes", function()
    it("Empty nodes", function()
      assert.are.same({}, sut.merge_nodes({}, {}))
    end)

    it("Identical nodes", function()
      local existing = {
        name = "Test",
        nodeType = "Test Plan",
        result = "Failed",
        children = {},
      }
      local node = {
        name = "Test",
        nodeType = "Test Plan",
        result = "Passed",
        children = {},
      }
      assert.are.same({ node }, sut.merge_nodes({ existing }, { node }))
    end)

    it("new into empty existing", function()
      local existing = {}
      local node = {
        name = "Test",
        nodeType = "Test Plan",
        result = "Passed",
        children = {},
      }
      assert.are.same({ node }, sut.merge_nodes(existing, { node }))
    end)

    it("new into existing", function()
      ---@type TestNode
      local existing = {
        name = "Test",
        nodeType = "Test Plan",
        result = "Passed",
        children = {
          {
            name = "Suite 1",
            nodeType = "Test Suite",
            result = "Passed",
            children = {
              {
                name = "Test",
                nodeType = "Test Case",
                result = "Passed",
                children = {},
              },
              {
                name = "Test 2",
                nodeType = "Test Case",
                result = "Passed",
                children = {},
              },
            },
          },
          {
            name = "Another Suite",
            nodeType = "Test Suite",
            result = "Passed",
            children = {
              {
                name = "Test 3",
                nodeType = "Test Case",
                result = "Passed",
                children = {},
              },
            },
          },
        },
      }
      ---@type TestNode
      local node = {
        name = "Test",
        nodeType = "Test Plan",
        result = "Failed",
        children = {
          {
            name = "Suite 1",
            nodeType = "Test Suite",
            result = "Failed",
            children = {
              {
                name = "Test",
                nodeType = "Test Case",
                result = "Failed",
                children = {},
              },
            },
          },
        },
      }

      local actual = sut.merge_nodes({ existing }, { node })
      ---@type TestNode[]
      local expected = {
        {
          name = "Test",
          nodeType = "Test Plan",
          result = "Failed",
          children = {
            {
              name = "Suite 1",
              nodeType = "Test Suite",
              result = "Failed",
              children = {
                {
                  name = "Test",
                  nodeType = "Test Case",
                  result = "Failed",
                  children = {},
                },
                {
                  name = "Test 2",
                  nodeType = "Test Case",
                  result = "unknown",
                  children = {},
                },
              },
            },
            {
              name = "Another Suite",
              nodeType = "Test Suite",
              result = "unknown",
              children = {
                {
                  name = "Test 3",
                  nodeType = "Test Case",
                  result = "unknown",
                  children = {},
                },
              },
            },
          },
        },
      }
      assert.are.same(actual, expected)
    end)
  end)

  describe("Test result tree", function()
    ---@return integer
    local function tree_buf_nr()
      local wins = vim.api.nvim_list_wins()
      return vim.api.nvim_win_get_buf(wins[#wins])
    end

    ---@return string[]
    local function tree_content()
      return vim.api.nvim_buf_get_lines(tree_buf_nr(), 0, -1, false)
    end

    ---@param keymap string
    local function invoke_keymap(keymap)
      local keymaps = vim.api.nvim_buf_get_keymap(tree_buf_nr(), "n")
      for _, mapping in ipairs(keymaps) do
        if mapping.lhs == keymap and mapping.callback then
          local ok, err = pcall(mapping.callback, mapping.lhs)

          assert.is_true(ok)
          assert.is_nil(err)
          return
        end
      end
    end

    it("show command opens a new window", function()
      local before = vim.api.nvim_list_wins()
      assert.are.equal(1, #before)
      sut.show({})

      local after = vim.api.nvim_list_wins()
      assert.are.equal(2, #after)
    end)

    it("show command with no tests", function()
      assert.are.same({ "  No tests found" }, tree_content())
    end)

    it("show command with tests", function()
      ---@type TestNode[]
      local results = {
        {
          name = "Test Plan 1",
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
                  nodeType = "Test Case",
                  result = "Passed",
                  children = {},
                },
              },
            },
          },
        },
        {
          name = "Test Plan 2",
          nodeType = "Test Plan",
          result = "Failed",
          children = {
            {
              name = "Test target 2",
              nodeType = "Unit test bundle",
              result = "Failed",
              children = {
                {
                  name = "Test Suite 2",
                  nodeType = "Test Suite",
                  result = "Failed",
                  children = {
                    {
                      name = "Test",
                      nodeType = "Test Case",
                      result = "Failed",
                      children = {},
                    },
                  },
                },
              },
            },
          },
        },
      }
      sut.show(results)

      assert.are.same({
        " [] Test Plan 1",
        " [] Test Plan 2",
      }, tree_content())

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      invoke_keymap("l")

      assert.are.same({
        " [] Test Plan 1",
        "   [] Test target",
        " [] Test Plan 2",
      }, tree_content())

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      invoke_keymap("l")

      assert.are.same({
        " [] Test Plan 1",
        "   [] Test target",
        "      [] Test",
        " [] Test Plan 2",
      }, tree_content())

      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      invoke_keymap("L")

      assert.are.same({
        " [] Test Plan 1",
        "   [] Test target",
        "      [] Test",
        " [] Test Plan 2",
        "   [] Test target 2",
        "     [] Test Suite 2",
        "        [] Test",
      }, tree_content())

      invoke_keymap("H")

      assert.are.same({
        " [] Test Plan 1",
        " [] Test Plan 2",
      }, tree_content())
    end)
  end)
end)
