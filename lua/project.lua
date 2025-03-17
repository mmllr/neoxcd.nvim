local nio = require("nio")
local util = require("util")
local types = require("types")
local simulator = require("simulator")
local runner = require("runner")

local M = {}

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
}

---@type DestinationCache
local destinations = {}
local diagnosticsNamespace = vim.api.nvim_create_namespace("neoxcd-diagnostics")
local marksNamespace = vim.api.nvim_create_namespace("neoxcd-marks")

local cmd = nio.wrap(util.run_job, 3)

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
      tests = {},
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
function M.load_schemes()
  local p = M.current_project
  if not p then
    return M.ProjectResult.NO_PROJECT
  end
  local opts = M.build_options_for_project(p)
  local result = nio.wrap(util.run_job, 3)(util.concat({ "xcodebuild", "-list", "-json" }, opts), nil)
  if result.code == 0 and result.stdout ~= nil then
    M.current_project.schemes = parse_schemes(result.stdout)
    save_project()
  end
  return result.code
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
  if p.scheme == scheme or p.type == "package" then
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
  local result = cmd({ "open", target.app_path })
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
local function ios_dap_config(program)
  return {
    {
      name = "iOS App Debugger",
      type = "lldb",
      request = "attach",
      program = program,
      cwd = "${workspaceFolder}",
      stopOnEntry = false,
      waitFor = true,
    },
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

  M.current_project.tests = {}
  nio.scheduler()
  local output = util.get_cwd() .. "/.neoxcd/tests.json"
  cmd({ "rm", "-rf", output }, nil)

  local build_cmd = {
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
  M.append_options_if_needed(build_cmd, M.current_project)
  local result = cmd(build_cmd, nil)

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
  M.current_project.tests = data.values
  return result.code
end

function M.show_runner()
  vim.cmd("botright 42vsplit Test Explorer")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  local results = M.current_project.test_results or M.current_project.tests
  local lines = results and #results > 0 and runner.format(results) or { "No tests found" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
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
---@return ProjectResultCode
function M.run_tests()
  if M.current_project == nil then
    return M.ProjectResult.NO_PROJECT
  elseif M.current_project.destination == nil then
    return M.ProjectResult.NO_DESTINATION
  elseif M.current_project.scheme == nil then
    return M.ProjectResult.NO_SCHEME
  end

  nio.scheduler()
  local results_path = util.get_cwd() .. "/.neoxcd/tests.xcresult"
  cmd({ "rm", "-rf", results_path }, nil)
  local opts = M.build_options_for_project(M.current_project)
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
    }, opts),
    nil
  )
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
    M.current_project.test_results = data.testNodes
    local quickfixes = update_quickfix_list(data.testNodes)
    if quickfixes and #quickfixes > 0 then
      M.current_project.quickfixes = quickfixes
      nio.scheduler()
      vim.fn.setqflist(quickfixes, "r")
    end
  end
  return result.code
end

---Gets all test failure nodes from the test results
---@param nodes TestNode[]
---@return TestNode[]
local function find_failed_nodes(nodes)
  local results = {}

  for _, node in ipairs(nodes) do
    if node.nodeType == "Test Case" and node.result == "Failed" then
      table.insert(results, node)
    end
    local child_results = find_failed_nodes(node.children or {})
    for _, child_result in ipairs(child_results) do
      table.insert(results, child_result)
    end
  end
  return results
end

---Updates the diagnostics list with the test results
---@param node TestNode
---@param buf integer
local function update_diagnostics_from_failure_message(node, buf)
  if node.nodeType ~= "Failure Message" then
    return
  end
  local diagnostics = {}
  local filepath = nio.api.nvim_buf_get_name(buf)

  local filename, line, message = string.match(node.name, "([^:]+):(%d+):%s*(.+)")
  if not util.has_suffix(filepath, filename) then
    return
  end

  table.insert(diagnostics, {
    bufnr = buf,
    lnum = line - 1,
    col = 0,
    severity = vim.diagnostic.severity.ERROR,
    source = "Neoxcd",
    message = message,
    user_data = {},
  })

  vim.diagnostic.reset(diagnosticsNamespace, buf)
  vim.api.nvim_buf_clear_namespace(buf, diagnosticsNamespace, 0, -1)
  vim.diagnostic.set(diagnosticsNamespace, buf, diagnostics, {})
end

---Updates the diagnostics in the test names
---async
---@param node TestNode
---@param buf integer
local function update_diagnostics_for_tests(node, buf)
  local class_name, method_name = runner.get_class_and_method(node.nodeIdentifier)
  if class_name == nil or method_name == nil then
    return
  end

  local lsp = nio.lsp
  local client = lsp.get_clients({ name = "sourcekit", bufnr = buf })[1]
  if client == nil then
    return
  end

  local err, response = client.request.textDocument_documentSymbol({ textDocument = { uri = vim.uri_from_bufnr(buf) } }, buf)
  if err or response == nil then
    return
  end

  local function find_class(symbols)
    for _, symbol in ipairs(symbols) do
      if symbol.name == class_name and symbol.kind == 5 or symbol.kind == 23 then -- '5' = Class
        nio.api.nvim_buf_set_extmark(buf, marksNamespace, symbol.range.start.line, 0, {
          virt_text = { { node.duration or "Failure", "DiagnosticVirtualTextError" } },
          sign_text = "",
          sign_hl_group = "DiagnosticSignError",
        })
        return symbol
      end
    end
  end

  -- Find the method inside the class
  local function find_method(class_symbol)
    if not class_symbol.children then
      return
    end
    for _, symbol in ipairs(class_symbol.children) do
      --https://github.com/swiftlang/sourcekit-lsp/blob/main/Sources/LanguageServerProtocol/SupportTypes/SymbolKind.swift
      if symbol.name == method_name and symbol.kind == 6 then -- '6' = Method
        nio.api.nvim_buf_set_extmark(buf, marksNamespace, symbol.range.start.line + 1, 0, {
          virt_text = { { node.duration or "Failure", "DiagnosticVirtualTextError" } },
          sign_text = "",
          sign_hl_group = "DiagnosticSignError",
        })
      end
    end
  end

  -- Search for the class first, then look for the method inside it
  local class_symbol = find_class(response)
  if class_symbol then
    find_method(class_symbol)
  end
end

---Updates a buffer with test results
---@async
---@param buf integer
M.update_test_results = function(buf)
  local results = M.current_project.test_results
  if results == nil or #results == 0 then
    return
  end
  local failure_nodes = find_failed_nodes(results)
  for _, node in pairs(failure_nodes) do
    update_diagnostics_for_tests(node, buf)
    local children = runner.children_with_type(node, "Failure Message")
    for _, child in ipairs(children) do
      update_diagnostics_from_failure_message(child, buf)
    end
  end
end

return M
