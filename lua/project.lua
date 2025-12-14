local nio = require("nio")
local util = require("util")
local types = require("types")
local simulator = require("simulator")
local runner = require("runner")

local M = {}

---Build issue class
---@class BuildIssue
---@field issueType string
---@field message string
---@field sourceURL? string

---Result code enum
---@alias ProjectResultCode integer

---@class ProjectResultConstants
---@field SUCCESS ProjectResultCode
---@field NO_PROJECT ProjectResultCode
---@field NO_SCHEME ProjectResultCode
---@field NO_DESTINATION ProjectResultCode
---@field NO_TARGET ProjectResultCode
---@field NO_SIMULATOR ProjectResultCode
---@field NO_XCODE ProjectResultCode
---@field INSTALL_FAILED ProjectResultCode
---@field NO_PROCESS ProjectResultCode
---@field NO_TESTS ProjectResultCode
---@field INVALID_JSON ProjectResultCode
---@field BUILD_FAILED ProjectResultCode

---@type ProjectResultConstants
M.ProjectResult = {
  SUCCESS = 0,
  NO_PROJECT = -1,
  NO_SCHEME = -2,
  NO_DESTINATION = -3,
  NO_TARGET = -4,
  NO_SIMULATOR = -5,
  NO_XCODE = -6,
  INSTALL_FAILED = -7,
  NO_PROCESS = -8,
  NO_TESTS = -9,
  INVALID_JSON = -10,
  BUILD_FAILED = -11,
}

---@type DestinationCache
local destinations = {}
local diagnosticsNamespace = vim.api.nvim_create_namespace("neoxcd-diagnostics")

local cmd = nio.wrap(util.run_job, 4)

---Parse the output of `xcodebuild -list -json` into a table of schemes
---@param input string
---@return string[]
local function parse_schemes(input)
  local schemes = {}
  local data = vim.json.decode(input)
  if data then
    local parent_key
    if data["project"] ~= nil then
      parent_key = "project"
    elseif data["workspace"] ~= nil then
      parent_key = "workspace"
    end
    if parent_key and data[parent_key]["schemes"] ~= nil then
      for _, scheme in ipairs(data[parent_key]["schemes"]) do
        table.insert(schemes, scheme)
      end
    end
  end
  return schemes
end

local function extract_fields(destination)
  -- { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:c0ffeec0-c0ffeec0ffeec0ff, name:My Mac }
  local result = {}
  for entry in vim.gsplit(destination, ", ", { plain = true }) do
    local key, value = entry:match("(%w+):(.+)")
    if key and value then
      if key == "error" then
        return nil
      end
      result[key] = value
    end
  end
  if vim.tbl_isempty(result) then
    return nil
  end
  return result
end

---Parse the output of `xcodebuild -showdestinations` into a table of destinations
---@param text string
---@return Destination[]
local function parse_destinations(text)
  local result = {}

  for block in text:gmatch("{(.-)}") do
    local destination = extract_fields(vim.trim(block))

    if destination ~= nil then
      table.insert(result, destination)
    end
  end

  return result
end

---Detects the project type
---@return ProjectResultCode
local function detect_project()
  local files = util.list_files(util.get_cwd())

  local function has_suffix(suffix)
    return function(file)
      return vim.endswith(file, suffix)
    end
  end

  local file = util.find_first(files, has_suffix(".xcworkspace"))
  if file ~= nil then
    M.current_project = { path = file, type = "workspace", schemes = {}, destinations = {}, tests = {} }
    return M.ProjectResult.SUCCESS
  end

  file = util.find_first(files, has_suffix(".xcodeproj"))
  if file ~= nil then
    M.current_project = { path = file, type = "project", schemes = {}, destinations = {}, tests = {} }
    return M.ProjectResult.SUCCESS
  end

  file = util.find_first(files, has_suffix("Package.swift"))
  if file ~= nil then
    M.current_project = { path = file, type = "package", schemes = {}, destinations = {}, tests = {} }
    return M.ProjectResult.SUCCESS
  end
  M.current_project = nil
  return M.ProjectResult.NO_PROJECT
end

---@type Project|nil
M.current_project = nil

---@type Target|nil
M.current_target = nil

---Loads the current project from saved json
---@async
---@return ProjectResultCode
local function load_project()
  nio.scheduler()
  local path = util.get_cwd() .. "/.neoxcd/project.json"
  local data = util.read_file(path)
  if data == nil then
    return M.ProjectResult.SUCCESS
  end
  local decoded = vim.json.decode(data)
  if decoded ~= nil and decoded.type and decoded.path and decoded.schemes then
    M.current_project = {
      name = decoded.name or "",
      path = decoded.path,
      type = decoded.type,
      scheme = decoded.scheme,
      destination = decoded.destination,
      schemes = decoded.schemes,
    }
    vim.g.neoxcd_scheme = decoded.scheme
    vim.g.neoxcd_destination = util.format_destination(decoded.destination)
    return M.ProjectResult.SUCCESS
  end
  return M.ProjectResult.INVALID_JSON
end

---Saves the current project to a json file
---@async
---@return ProjectResultCode
local function save_project()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  end
  local data = {
    name = M.current_project.name,
    path = M.current_project.path,
    type = M.current_project.type,
    scheme = M.current_project.scheme,
    destination = M.current_project.destination,
    schemes = M.current_project.schemes,
  }
  nio.scheduler()
  local path = util.get_cwd() .. "/.neoxcd/project.json"
  local result = util.write_file(path, vim.json.encode(data))
  if result then
    return M.ProjectResult.SUCCESS
  else
    return M.ProjectResult.INVALID_JSON
  end
end

---Saves the destinations to a json file
---@async
---@return ProjectResultCode
local function save_destinations()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  end
  nio.scheduler()
  local path = util.get_cwd() .. "/.neoxcd/destinations.json"
  local result = util.write_file(path, vim.json.encode(destinations))
  if result then
    return M.ProjectResult.SUCCESS
  else
    return M.ProjectResult.INVALID_JSON
  end
end

---Loads the destinations from a json file
---@async
---@return ProjectResultCode
local function load_cached_destinations()
  nio.scheduler()
  local path = util.get_cwd() .. "/.neoxcd/destinations.json"
  local data = util.read_file(path)
  if data ~= nil then
    local result, dst = pcall(vim.json.decode, data, { luanil = { object = true, array = true } })
    if result then
      destinations = dst
      return M.ProjectResult.SUCCESS
    end
  end
  return M.ProjectResult.INVALID_JSON
end

---Loads the project file in the current directory
---@async
---@return ProjectResultCode
function M.load()
  local result = detect_project()
  if result ~= M.ProjectResult.SUCCESS then
    return result
  end

  cmd({ "mkdir", "-p", util.get_cwd() .. "/.neoxcd" }, nil)

  load_cached_destinations()
  return load_project()
end

---Returns the builld options for a project
---@param project Project
---@return string[]
function M.build_options_for_project(project)
  if project.type == "package" or #project.path == 0 then
    return {}
  end
  return { "-" .. project.type, project.path }
end

--- Find the Xcode workspace or project file in the current directory
--- When no result is found, return empty table (Swift package projects do not have a workspace or project file)
---@return string[]|nil
function M.find_build_options()
  if M.current_project ~= nil then
    return M.build_options_for_project(M.current_project)
  end
  return nil
end

---Load the schemes for the current project
---@async
---@return ProjectResultCode
---@return string? stderr
function M.load_schemes()
  local p = M.current_project
  if not p then
    return M.ProjectResult.NO_PROJECT
  end
  local opts = M.build_options_for_project(p)
  local result = nio.wrap(util.run_job, 4)(util.concat({ "xcodebuild", "-list", "-json" }, opts), nil)
  if result.code == 0 and result.stdout ~= nil then
    M.current_project.schemes = parse_schemes(result.stdout)
    save_project()
  end
  return result.code, result.stderr
end

---@async
---@return string[]
local function local_package_schemes()
  local schemes = {}
  local result = cmd({ "find", ".", "-type", "f", "-name", "*.xcscheme", "-path", "*/.swiftpm/*" }, nil)
  if result.code == 0 and result.stdout ~= nil then
    local lines = vim.split(result.stdout, "[\r]?\n", { trimempty = true })
    for _, line in ipairs(lines) do
      local scheme = line:match("([^/]+)%.xcscheme$")
      if scheme ~= nil then
        table.insert(schemes, scheme)
      end
    end
  end
  return schemes
end

---selects a scheme
---@async
---@param scheme string
---@return ProjectResultCode
function M.select_scheme(scheme)
  local p = M.current_project
  if not p then
    return M.ProjectResult.NO_PROJECT
  elseif p.schemes == nil and not vim.list_contains(p.schemes, scheme) then
    return M.ProjectResult.NO_SCHEME
  end
  local package_schemes = local_package_schemes()
  if p.scheme == scheme or p.type == "package" or vim.list_contains(package_schemes, scheme) then
    M.current_project.scheme = scheme
    vim.g.neoxcd_scheme = scheme
    return M.ProjectResult.SUCCESS
  end
  local opts = M.build_options_for_project(p)
  local result = cmd(util.concat({ "xcode-build-server", "config", "-scheme", scheme }, opts), nil)
  if result.code == M.ProjectResult.SUCCESS then
    M.current_project.scheme = scheme
    vim.g.neoxcd_scheme = scheme
  end
  save_project()
  return result.code
end

---Loads selects a destination for the current scheme
---@async
---@return number
function M.load_destinations()
  local p = M.current_project
  if not p then
    return M.ProjectResult.NO_PROJECT
  end
  if not p.scheme then
    return M.ProjectResult.NO_SCHEME
  end

  local opts = M.build_options_for_project(p)
  local result = cmd(util.concat({ "xcodebuild", "-showdestinations", "-scheme", p.scheme, "-quiet" }, opts), nil)
  if result.code == M.ProjectResult.SUCCESS and result.stdout then
    destinations[p.scheme] = parse_destinations(result.stdout)
    return save_destinations()
  end
  return result.code
end

---Select a destination
---@async
---@param index number
function M.select_destination(index)
  if M.current_project == nil or M.current_project.scheme == nil or destinations[M.current_project.scheme] == nil then
    return
  end
  M.current_project.destination = destinations[M.current_project.scheme][index]
  vim.g.neoxcd_destination = util.format_destination(M.current_project.destination)
  save_project()
end

---Returns the available destinations for the currently selected scheme
---@return Destination|nil Nil when no project is loaded or no scheme is selected
function M.destinations()
  return M.current_project and M.current_project.scheme and destinations[M.current_project.scheme] or nil
end

---Opens the current project in Xcode
---@async
---@return ProjectResultCode
function M.open_in_xcode()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  end
  local result = cmd({ "xcode-select", "-p" }, nil)
  if result.code ~= M.ProjectResult.SUCCESS or result.stdout == nil then
    return M.ProjectResult.NO_XCODE
  end
  local xcode_path = util.remove_n_components(result.stdout, 2)

  result = cmd({ "open", xcode_path, M.current_project.path })
  return result.code
end

---Runs the current project in the simulator
---@async
---@param project Project
---@param target Target
---@param waitForDebugger boolean
---@return ProjectResultCode
local function run_on_simulator(project, target, waitForDebugger)
  local result = simulator.install_on_simulator(project.destination, target.app_path)
  if result ~= simulator.SimulatorResult.OK then
    return result
  end
  result = cmd(
    util.lst_remove_nil_values({
      "xcrun",
      "simctl",
      "launch",
      "--terminate-running-process",
      "--console-pty",
      waitForDebugger and "--wait-for-debugger" or nil,
      project.destination.id,
      target.bundle_id,
    }),
    nil
  )
  return result.code
end

---Runs the current project locally
---@async
---@param target Target
---@return ProjectResultCode
local function run_on_mac(target)
  local result = cmd({ "open", target.app_path }, nil)
  return result.code
end

---Runs the current project
---@async
---@return number
function M.run()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_target == nil then
    return M.ProjectResult.NO_TARGET
  elseif M.current_project.destination == nil then
    return M.ProjectResult.NO_DESTINATION
  end
  if M.current_project.destination.platform == types.Platform.IOS_SIMULATOR then
    return run_on_simulator(M.current_project, M.current_target, false)
  elseif M.current_project.destination.platform == types.Platform.MACOS then
    return run_on_mac(M.current_target)
  else
    return M.ProjectResult.NO_DESTINATION
  end
end

---@param program string
---@return dap.Configuration
local function ios_dap_config(program)
  return {
    name = "iOS App Debugger",
    type = "codelldb",
    request = "attach",
    program = program,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    waitFor = true,
  }
end

---@param program string
local function macos_dap_config(program)
  return {
    name = "macOS Debugger",
    type = "lldb",
    request = "launch",
    cwd = "${workspaceFolder}",
    program = program,
    args = {},
    stopOnEntry = false,
    waitFor = true,
    env = {},
  }
end

---@async
---@param project  Project
---@param target Target
---@return ProjectResultCode
local function debug_on_simulator(project, target)
  util.run_dap(ios_dap_config(target.app_path))
  return run_on_simulator(project, target, true)
end

---Updates the quickfix list with the build errors
---@param issues BuildIssue[]
---@return QuickfixEntry[]
local function update_quickfix_list_from_build_issues(issues)
  local quickfix_list = {}

  local function parse_source_url(url)
    local file = url:match("file://([^#]+)")
    local start_column = url:match("StartingColumnNumber=(%d+)")
    local start_line = url:match("StartingLineNumber=(%d+)")
    return file, tonumber(start_column), tonumber(start_line)
  end

  for _, issue in ipairs(issues) do
    if issue.sourceURL then
      local file, start_column, start_line = parse_source_url(issue.sourceURL)
      if file and start_column and start_line then
        local entry = {
          filename = file,
          lnum = start_line + 1,
          col = start_column,
          text = issue.message,
          type = types.QuickfixEntryType.ERROR,
        }
        table.insert(quickfix_list, entry)
      end
    end
  end
  return quickfix_list
end

---Updates the build results to the quickfix list
---@async
---@param results_path string
---@return ProjectResultCode
local function update_build_results(results_path)
  local build_results = cmd({ "xcrun", "xcresulttool", "get", "build-results", "--path", results_path, "--compact" }, nil)
  if build_results.code == 0 and build_results.stdout then
    local data = vim.json.decode(build_results.stdout, {
      luanil = {
        object = true,
        array = true,
      },
    })
    if data == nil or data.errors == nil then
      return M.ProjectResult.INVALID_JSON
    end
    local quickfixes = update_quickfix_list_from_build_issues(data.errors)
    if quickfixes and #quickfixes > 0 then
      M.current_project.quickfixes = quickfixes
      nio.scheduler()
      vim.fn.setqflist(quickfixes, "r")
      return M.ProjectResult.BUILD_FAILED
    end
  end
  return build_results.code
end

---Parses a list of TestEnumerations into a list of TestNodes
---@param enumerations TestEnumeration[]
---@return TestNode[]
local function parse_discovered_tests(enumerations)
  ---@type table<TestEnumerationKind, TestNodeType>
  local kind_to_node_type = {
    ["plan"] = "Test Plan",
    ["target"] = "Unit test bundle",
    ["class"] = "Test Suite",
    ["test"] = "Test Case",
  }

  ---@param enumeration TestEnumeration
  ---@return TestNode?
  local function convert(enumeration)
    local type = kind_to_node_type[enumeration.kind]
    if not type then
      return nil
    end
    ---@type TestNode
    local node = {
      name = enumeration.name,
      nodeType = type,
      result = "unknown",
    }
    local child_nodes = {}
    for _, child in ipairs(enumeration.children or {}) do
      local child_node = convert(child)
      if child_node ~= nil then
        if enumeration.kind == "class" and child.kind == "test" then
          child_node.nodeIdentifier = enumeration.name .. "/" .. child.name
        end
        table.insert(child_nodes, child_node)
      end
    end
    if #child_nodes > 0 then
      node.children = child_nodes
    end
    return node
  end

  local nodes = {}
  for _, enumeration in ipairs(enumerations) do
    local node = convert(enumeration)
    if node ~= nil then
      table.insert(nodes, node)
    end
  end
  return nodes
end

---Debugs the current project
---@async
---@return ProjectResultCode
function M.debug()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_target == nil then
    return M.ProjectResult.NO_TARGET
  elseif M.current_project.destination == nil then
    return M.ProjectResult.NO_DESTINATION
  end
  if M.current_project.destination.platform == types.Platform.IOS_SIMULATOR then
    return debug_on_simulator(M.current_project, M.current_target)
  elseif M.current_project.destination.platform == types.Platform.MACOS then
    util.run_dap(macos_dap_config(M.current_target.app_path))
  end

  return M.ProjectResult.SUCCESS
end

---Stops the currently running target
---@async
---@return ProjectResultCode
function M.stop()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_target == nil then
    return M.ProjectResult.NO_TARGET
  end
  local result = cmd({ "pgrep", M.current_target.name }, nil)
  if result.code == 0 and result.stdout then
    local pid = tonumber(result.stdout)
    if not pid then
      return M.ProjectResult.NO_PROCESS
    end

    result = cmd({ "kill", "-9", pid }, nil)
  end
  return result.code
end

---@param command string[]
---@param project Project
function M.append_options_if_needed(command, project)
  local opts = M.build_options_for_project(project)
  if not vim.tbl_isempty(opts) then
    vim.list_extend(command, opts)
  end
end

---Discover tests in the current project
---@async
---@return ProjectResultCode
function M.discover_tests()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_project.destination == nil then
    return M.ProjectResult.NO_DESTINATION
  end

  M.current_project.test_results = {}
  nio.scheduler()
  local results_path = util.get_cwd() .. "/.neoxcd/scan.xcresult"
  local opts = M.build_options_for_project(M.current_project)
  local output = util.get_cwd() .. "/.neoxcd/tests.json"
  cmd({ "rm", "-rf", output }, nil)
  cmd({ "rm", "-rf", results_path }, nil)

  local build_cmd = {
    "xcodebuild",
    "build-for-testing",
    "-scheme",
    M.current_project.scheme,
    "-destination",
    "id=" .. M.current_project.destination.id,
    "-resultBundlePath",
    results_path,
  }
  local build_result = cmd(util.concat(build_cmd, opts), nil)
  if build_result.code ~= 0 then
    local code = update_build_results(results_path)
    return code == M.ProjectResult.SUCCESS and build_result.code or code
  end

  local test_cmd = {
    "xcodebuild",
    "test-without-building",
    "-scheme",
    M.current_project.scheme,
    "-destination",
    "id=" .. M.current_project.destination.id,
    "-enumerate-tests",
    "-test-enumeration-format",
    "json",
    "-test-enumeration-output-path",
    output,
    "-test-enumeration-style",
    "hierarchical",
    "-disableAutomaticPackageResolution",
    "-skipPackageUpdates",
  }
  local result = cmd(util.concat(test_cmd, opts), nil)

  if result.code ~= 0 then
    return result.code
  end

  local json = util.read_file(output)
  if json == nil then
    return M.ProjectResult.NO_TESTS
  end

  local data = vim.json.decode(json, {
    luanil = {
      object = true,
      array = true,
    },
  })
  if data == nil or data.values == nil then
    return M.ProjectResult.INVALID_JSON
  end
  M.current_project.test_results = parse_discovered_tests(data.values)
  return result.code
end

function M.show_runner()
  runner.show(M.current_project.test_results)
end

---Gets all failure message nodes from the test results
---@param nodes TestNode[]
---@return TestNode[]
local function find_failure_message_nodes(nodes)
  local results = {}

  for _, node in ipairs(nodes) do
    if node.nodeType == "Failure Message" then
      table.insert(results, node)
    else
      if node.children then
        local child_results = find_failure_message_nodes(node.children)
        for _, child_result in ipairs(child_results) do
          table.insert(results, child_result)
        end
      end
    end
  end
  return results
end

---Updates the quickfix list with the test results. It transforms all failure message nodes iunto quickfix entries
---@async
---@param tests TestNode[]
---@return QuickfixEntry[]
local function update_quickfix_list(tests)
  local quickfix_list = {}
  local failure_nodes = find_failure_message_nodes(tests)
  for _, test in ipairs(failure_nodes) do
    local filename, line, rest = test.name:match("([^:]+):(%d+):%s*(.+)")
    if filename and line and rest then
      local find_result = cmd({ "fd", "^" .. filename }, nil)
      if find_result.code == 0 and find_result.stdout then
        local entry = {
          filename = string.gsub(find_result.stdout, "\n$", ""),
          lnum = tonumber(line),
          text = rest,
          type = types.QuickfixEntryType.ERROR,
        }
        table.insert(quickfix_list, entry)
      end
    end
  end
  return quickfix_list
end

---Runs the tests in the current project
---@async
---@param testIdentifier? string
---@return ProjectResultCode
function M.run_tests(testIdentifier)
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_project.destination == nil then
    return M.ProjectResult.NO_DESTINATION
  elseif M.current_project.scheme == nil then
    return M.ProjectResult.NO_SCHEME
  end

  vim.fn.setqflist({}, "r")
  nio.scheduler()
  local results_path = util.get_cwd() .. "/.neoxcd/tests.xcresult"
  cmd({ "rm", "-rf", results_path }, nil)
  local opts = M.build_options_for_project(M.current_project)
  local selected_tests = testIdentifier and { "-only-testing:" .. testIdentifier } or {}
  local result = cmd(
    util.concat({
      "xcodebuild",
      "test",
      "-scheme",
      M.current_project.scheme,
      "-destination",
      "id=" .. M.current_project.destination.id,
      "-resultBundlePath",
      results_path,
    }, opts, selected_tests),
    nil
  )

  if result.code ~= 0 then
    local update_result = update_build_results(results_path)
    if update_result ~= M.ProjectResult.SUCCESS then
      return update_result
    end
  end
  local test_result = cmd({
    "xcrun",
    "xcresulttool",
    "get",
    "test-results",
    "tests",
    "--path",
    results_path,
    "--compact",
  }, nil)
  if test_result.code == 0 and test_result.stdout then
    local data = vim.json.decode(test_result.stdout, {
      luanil = {
        object = true,
        array = true,
      },
    })
    if data == nil or data.testNodes == nil then
      return M.ProjectResult.INVALID_JSON
    end
    if testIdentifier and M.current_project.test_results then
      M.current_project.test_results = runner.merge_nodes(M.current_project.test_results, data.testNodes)
    else
      M.current_project.test_results = data.testNodes
    end
    local quickfixes = update_quickfix_list(data.testNodes)
    if quickfixes and #quickfixes > 0 then
      M.current_project.quickfixes = quickfixes
      nio.scheduler()
      vim.fn.setqflist(quickfixes, "r")
    end
  end
  return result.code
end

---@param buf integer
---@param diag TestDiagnostic
local function add_diagnostic_to_buffer(buf, diag)
  if diag.kind == "failure" then
    vim.diagnostic.set(diagnosticsNamespace, buf, {
      {
        lnum = diag.line,
        col = 0,
        severity = diag.severity,
        source = "Neoxcd",
        message = diag.message,
        user_data = {},
      },
    }, {
      virtual_lines = true,
      virtual_text = false,
    })
  elseif diag.kind == "symbol" then
    nio.api.nvim_buf_set_extmark(buf, diagnosticsNamespace, diag.line, 0, {
      virt_text = {
        { diag.message, runner.virtual_highlight_for_result(diag.result) },
      },
      sign_text = runner.icon_for_result(diag.result),
      sign_hl_group = runner.highlight_for_result(diag.result),
    })
  end
end

---Updates a buffer with test results
---@async @param buf integer
function M.update_test_results(buf)
  local results = M.current_project.test_results
  if results == nil or #results == 0 then
    return
  end
  local diags = runner.diagnostics_for_tests_in_buffer(buf, results)
  vim.diagnostic.reset(diagnosticsNamespace, buf)
  vim.api.nvim_buf_clear_namespace(buf, diagnosticsNamespace, 0, -1)
  for _, diag in ipairs(diags or {}) do
    add_diagnostic_to_buffer(buf, diag)
  end
end

return M
