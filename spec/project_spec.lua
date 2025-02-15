local assert = require("luassert")
local types = require("types")
local util = require("util")
local helpers = require("spec/helpers")

describe("neoxcd plugin", function()
  local nio = require("nio")
  local it = nio.tests.it
  local project = require("project")
  ---@type table<string, StubbedCommand>
  local stubbed_commands = {}

  ---@param type ProjectType
  ---@param scheme string|nil
  ---@param schemes string[]|nil
  ---@param destination Destination|nil
  ---@param destinations Destination[]|nil
  local function givenProject(type, scheme, schemes, destination, destinations)
    project.current_project = {
      type = type,
      path = type == "project" and "project.xcodeproj" or "project.xcworkspace",
      destination = destination,
      schemes = schemes or {},
      scheme = scheme,
      destinations = destinations or {},
    }
  end

  ---@param path string
  ---@param bundle_id string
  local function givenTarget(path, bundle_id)
    project.current_target = {
      app_path = path,
      bundle_id = bundle_id,
      name = "TestApp",
      plist = "TestApp/Info.plist",
      module_name = "TestApp",
    }
  end

  before_each(function()
    stubbed_commands = {}
    util.setup({
      run_cmd = helpers.setup_run_cmd(stubbed_commands),
    })
    project.current_project = nil
    project.current_target = nil
  end)

  after_each(function()
    assert.are.same(stubbed_commands, {}, "The following commands where expected to be invoked: " .. vim.inspect(stubbed_commands))
  end)

  ---@param code number|number[]
  ---@param stubbed_cmd string[]
  ---@param output string
  local function stub_external_cmd(code, stubbed_cmd, output)
    stubbed_commands[table.concat(stubbed_cmd, " ")] = { code = code, output = output, use_on_stdout = false }
  end

  teardown(function()
    project = nil
  end)

  describe("Scheme handling", function()
    it("Parsing output from workspace", function()
      local json = [[
{
  "workspace" : {
    "name" : "ComposableArchitecture",
    "schemes" : [
      "CaseStudies (SwiftUI)",
      "CaseStudies (UIKit)",
      "ComposableArchitecture",
      "Integration",
      "Search",
      "Sharing",
      "SharingTests",
      "SpeechRecognition",
      "swift-composable-architecture-benchmark",
      "SyncUps",
      "TicTacToe",
      "Todos",
      "tvOSCaseStudies",
      "VoiceMemos"
    ]
  }
}
  ]]
      givenProject("workspace")
      stub_external_cmd(0, { "xcodebuild", "-list", "-json", "-workspace", "project.xcworkspace" }, json)
      local expected = {
        "CaseStudies (SwiftUI)",
        "CaseStudies (UIKit)",
        "ComposableArchitecture",
        "Integration",
        "Search",
        "Sharing",
        "SharingTests",
        "SpeechRecognition",
        "swift-composable-architecture-benchmark",
        "SyncUps",
        "TicTacToe",
        "Todos",
        "tvOSCaseStudies",
        "VoiceMemos",
      }

      project.load_schemes()

      assert.are.same(expected, project.current_project.schemes)
    end)

    it("Parsing output from project", function()
      local json = [[
{
  "project" : {
    "configurations" : [
      "Debug",
      "Release"
    ],
    "name" : "ProjectName",
    "schemes" : [
      "SchemeA",
      "SchemeB"
    ],
    "targets" : [
      "TargetA",
      "TargetB"
    ]
  }
}
  ]]
      local expected = {
        "SchemeA",
        "SchemeB",
      }
      givenProject("project")
      stub_external_cmd(0, { "xcodebuild", "-list", "-json", "-project", "project.xcodeproj" }, json)

      assert.are.same(0, project.load_schemes())

      assert.are.same(expected, project.current_project.schemes)
    end)

    it("Selecting a scheme will update the xcode build server", function()
      givenProject("project", nil, { "schemeA", "SchemeB", "schemeC" })
      stub_external_cmd(0, { "xcode-build-server", "config", "-scheme", "schemeB", "-project", "project.xcodeproj" }, "")

      assert.are.same(0, project.select_scheme("schemeB"))
      assert.are.same("schemeB", project.current_project.scheme)
    end)

    it("Will not update the xcode build server when selecting the same scheme", function()
      givenProject("project", "schemeA", { "schemeA", "SchemeB", "schemeC" })
      local result = project.select_scheme("schemeA")

      assert.are.same(0, result)
      assert.are.same("schemeA", project.current_project.scheme)
    end)

    it("Will not update the xcode build server for Swift packages", function()
      givenProject("package", nil, { "schemeA", "SchemeB", "schemeC" })
      local result = project.select_scheme("schemeA")

      assert.are.same(0, result)
      assert.are.same("schemeA", project.current_project.scheme)
    end)
  end)

  describe("Destination parsing", function()
    it("Parsing output from xcodebuild -showdestinations", function()
      local output = [[


        Available destinations for the "ComposableArchitecture" scheme:
                { platform:macOS, arch:arm64e, id:deadbeef-deadbeefdeadbeef, name:My Mac }
                { platform:macOS, arch:arm64e, variant:Mac Catalyst, id:deadbeef-deadbeefdeadbeef, name:My Mac }
                { platform:macOS, arch:arm64, variant:DriverKit, id:deadbeef-deadbeefdeadbeef, name:My Mac }
                { platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:c0ffeec0-c0ffeec0ffeec0ff, name:My Mac }
                { platform:iOS, arch:arm64e, id:c0ffeec0-c0ffeec0ffeec0ff, name:Meins }
                { platform:DriverKit, name:Any DriverKit Host }
                { platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device }
                { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
                { platform:macOS, name:Any Mac }
                { platform:macOS, variant:Mac Catalyst, name:Any Mac }
                { platform:iOS Simulator, id:99030200-5D08-471A-9F69-A667A38F0DD6, OS:17.5, name:iPad (10th generation) }
                { platform:iOS Simulator, id:48BF3B63-0C44-48F0-AA55-A027D2221550, OS:18.2, name:iPad (10th generation) }
                { platform:iOS Simulator, id:277E7397-BEB6-4F5A-8095-715C9FFB396F, OS:15.5, name:iPhone 6s }
                { platform:iOS Simulator, id:E44A13CA-AF60-4ED4-A9B8-EE59D0B5A01F, OS:18.2, name:iPhone 16 Plus }
                { platform:iOS Simulator, id:78379CC1-79BE-4C8B-ACAD-730424A40DFC, OS:18.2, name:iPhone 16 Pro }
                { platform:iOS Simulator, id:361683D0-8D89-4D66-8BA7-BF93F34B31EE, OS:18.2, name:iPhone 16 Pro Max }
                { platform:iOS Simulator, id:D6DAB6A2-EC1E-4CF0-A0D3-8A0C63F3CEB0, OS:17.5, name:iPhone SE (3rd generation) }

        Ineligible destinations for the "ComposableArchitecture" scheme:
                { platform:tvOS, id:dvtdevice-DVTiOSDevicePlaceholder-appletvos:placeholder, name:Any tvOS Device, error:tvOS 18.2 is not installed. To use with Xcode, first download and install the platform }
                { platf ,orm:visionOS, id:dvtdevice-DVTiOSDevicePlaceholder-xros:placeholder, name:Any visionOS Device, error:visionOS 2.2 is not installed. To use with Xcode, first download and install the platform }
                { platform:watchOS, id:dvtdevice-DVTiOSDevicePlaceholder-watchos:placeholder, name:Any watchOS Device, error:watchOS 11.2 is not installed. To use with Xcode, first download and install the platform }
      ]]

      givenProject("project", "testScheme")
      stub_external_cmd(
        0,
        { "xcodebuild", "-showdestinations", "-scheme", "testScheme", "-quiet", "-project", "project.xcodeproj" },
        output
      )
      local expected = {
        { platform = "macOS", arch = "arm64e", id = "deadbeef-deadbeefdeadbeef", name = "My Mac" },
        {
          platform = "macOS",
          arch = "arm64e",
          variant = "Mac Catalyst",
          id = "deadbeef-deadbeefdeadbeef",
          name = "My Mac",
        },
        {
          platform = "macOS",
          arch = "arm64",
          variant = "DriverKit",
          id = "deadbeef-deadbeefdeadbeef",
          name = "My Mac",
        },
        {
          platform = "macOS",
          arch = "arm64",
          variant = "Designed for [iPad,iPhone]",
          id = "c0ffeec0-c0ffeec0ffeec0ff",
          name = "My Mac",
        },
        { platform = "iOS", arch = "arm64e", id = "c0ffeec0-c0ffeec0ffeec0ff", name = "Meins" },
        { name = "Any DriverKit Host", platform = "DriverKit" },
        { name = "Any iOS Device", platform = "iOS", id = "dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder" },
        {
          name = "Any iOS Simulator Device",
          platform = "iOS Simulator",
          id = "dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder",
        },
        { name = "Any Mac", platform = "macOS" },
        { name = "Any Mac", platform = "macOS", variant = "Mac Catalyst" },
        {
          platform = "iOS Simulator",
          id = "99030200-5D08-471A-9F69-A667A38F0DD6",
          OS = "17.5",
          name = "iPad (10th generation)",
        },
        {
          platform = "iOS Simulator",
          id = "48BF3B63-0C44-48F0-AA55-A027D2221550",
          name = "iPad (10th generation)",
          OS = "18.2",
        },
        { OS = "15.5", id = "277E7397-BEB6-4F5A-8095-715C9FFB396F", name = "iPhone 6s", platform = "iOS Simulator" },
        {
          OS = "18.2",
          id = "E44A13CA-AF60-4ED4-A9B8-EE59D0B5A01F",
          name = "iPhone 16 Plus",
          platform = "iOS Simulator",
        },
        {
          OS = "18.2",
          id = "78379CC1-79BE-4C8B-ACAD-730424A40DFC",
          name = "iPhone 16 Pro",
          platform = "iOS Simulator",
        },
        {
          OS = "18.2",
          id = "361683D0-8D89-4D66-8BA7-BF93F34B31EE",
          name = "iPhone 16 Pro Max",
          platform = "iOS Simulator",
        },
        {
          OS = "17.5",
          id = "D6DAB6A2-EC1E-4CF0-A0D3-8A0C63F3CEB0",
          name = "iPhone SE (3rd generation)",
          platform = "iOS Simulator",
        },
      }
      assert.are.same(0, project.load_destinations())
      assert.are.same(expected, project.destinations())
    end)
  end)

  describe("Destination format for UI", function()
    --@type Destination
    local destination
    it("Format a mac", function()
      destination = { name = "My Mac", platform = "macOS", arch = "arm64" }
      assert.are.equal("󰇄 My Mac", util.format_destination(destination))
    end)

    it("Format a mac with variant", function()
      destination = { name = "My Mac", platform = "macOS", variant = "Mac Catalyst" }
      assert.are.equal("󰇄 My Mac (Mac Catalyst)", util.format_destination(destination))
    end)

    it("Formats a tvOS", function()
      destination = { name = "Any tvOS Device", platform = "tvOS" }
      assert.are.equal(" Any tvOS Device", util.format_destination(destination))
    end)

    it("Formats a watchOS", function()
      destination = { name = "Any watchOS Device", platform = "watchOS" }
      assert.are.equal("󰢗 Any watchOS Device", util.format_destination(destination))
    end)

    it("Formats any simulator", function()
      destination = { name = "Any iOS Simulator Device", platform = "iOS Simulator" }
      assert.are.equal("󰦧 Any iOS Simulator Device", util.format_destination(destination))
    end)

    it("Formats a phone specific simulator", function()
      destination = { name = "iPhone 6s", platform = "iOS Simulator", OS = "15.5" }
      assert.are.equal(" iPhone 6s (15.5)", util.format_destination(destination))
    end)

    it("Formats a tablet specific simulator", function()
      destination = { name = "iPad Air", platform = "iOS Simulator", OS = "18.2" }
      assert.are.equal("󰓶 iPad Air (18.2)", util.format_destination(destination))
    end)

    it("Formats a DriverKit platform", function()
      destination = { name = "Any DriverKit Host", platform = "DriverKit" }
      assert.are.equal("󰇄 Any DriverKit Host", util.format_destination(destination))
    end)
  end)

  it("Can select a destination", function()
    local output = [[


        Available destinations for the "testScheme" scheme:
                { platform:iOS Simulator, id:78379CC1-79BE-4C8B-ACAD-730424A40DFC, OS:18.2, name:iPhone 16 Pro }
                { platform:iOS Simulator, id:361683D0-8D89-4D66-8BA7-BF93F34B31EE, OS:18.2, name:iPhone 16 Pro Max }
      ]]

    givenProject("project", "testScheme")
    stub_external_cmd(0, { "xcodebuild", "-showdestinations", "-scheme", "testScheme", "-quiet", "-project", "project.xcodeproj" }, output)

    local destinations = {
      {
        OS = "18.2",
        id = "78379CC1-79BE-4C8B-ACAD-730424A40DFC",
        name = "iPhone 16 Pro",
        platform = "iOS Simulator",
      },
      {
        OS = "18.2",
        id = "361683D0-8D89-4D66-8BA7-BF93F34B31EE",
        name = "iPhone 16 Pro Max",
        platform = "iOS Simulator",
      },
    }

    ---@type Project
    project.current_project = {
      path = "project.xcodeproj",
      type = "project",
      scheme = "testScheme",
      schemes = { "testScheme" },
    }
    project.load_destinations()
    project.select_scheme("testScheme")

    for i, d in ipairs(destinations) do
      project.select_destination(i)
      assert.are.same(d, project.current_project.destination)
    end
  end)

  it("Can open the project in Xcode", function()
    givenProject("project", "testScheme")
    stub_external_cmd(0, { "xcode-select", "-p" }, "/Applications/Xcode-16.2.app/Contents/Developer")
    stub_external_cmd(0, { "open", "/Applications/Xcode-16.2.app", "project.xcodeproj" }, "")
    assert.are.same(0, project.open_in_xcode())
  end)

  it("Running a target on simulator with no simulator booted", function()
    ---@type Destination
    local simulator_dest = {
      platform = types.Platform.IOS_SIMULATOR,
      id = "78379CC1-79BE-4C8B-ACAD-730424A40DFC",
      name = "iPhone 16 Pro",
    }
    givenProject("project", "testScheme", {}, simulator_dest)
    givenTarget("/path/to/build/TestApp.app", "com.test.TestApp")
    stub_external_cmd(0, { "xcode-select", "-p" }, "/Applications/Xcode-16.2.app/Contents/Developer\n")
    stub_external_cmd(0, { "xcrun", "simctl", "boot", simulator_dest.id }, "")
    stub_external_cmd(0, { "open", "/Applications/Xcode-16.2.app/Contents/Developer/Applications/Simulator.app" }, "")
    stub_external_cmd({ 149, 0 }, { "xcrun", "simctl", "install", simulator_dest.id, "/path/to/build/TestApp.app" }, "")
    stub_external_cmd(0, {
      "xcrun",
      "simctl",
      "launch",
      "--terminate-running-process",
      "--console-pty",
      simulator_dest.id,
      "com.test.TestApp",
    }, "")

    assert.are.same(0, project.run())
  end)

  it("Running a target on macOS", function()
    ---@type Destination
    local mac_dest = {
      platform = types.Platform.MACOS,
      arch = "arm64",
      name = "My Mac",
      id = "deadbeef-deadbeefdeadbeef",
    }
    givenProject("project", "testScheme", {}, mac_dest)
    givenTarget("/path/to/build/TestApp.app", "com.test.TestApp")
    stub_external_cmd(0, { "open", "/path/to/build/TestApp.app" }, "")
    assert.are.same(0, project.run())
  end)

  describe("Debugging", function()
    local stubbed_dap = {}

    before_each(function()
      stubbed_dap = {}
      util.setup({
        run_dap = function(conf)
          stubbed_dap = conf
        end,

        run_cmd = helpers.setup_run_cmd(stubbed_commands),
      })
    end)

    it("macOS application", function()
      ---@type Destination
      local mac_dest = {
        platform = types.Platform.MACOS,
        arch = "arm64",
        name = "My Mac",
        id = "deadbeef-deadbeefdeadbeef",
      }
      givenProject("project", "testScheme", {}, mac_dest)
      givenTarget("/path/to/build/TestApp.app", "com.test.TestApp")

      assert.are.same(0, project.debug())
      assert.are.same({
        name = "macOS Debugger",
        type = "lldb",
        request = "launch",
        cwd = "${workspaceFolder}",
        program = "/path/to/build/TestApp.app",
        args = {},
        stopOnEntry = false,
        waitFor = true,
        env = {},
      }, stubbed_dap)
    end)

    it("iOS simulator application", function()
      ---@type Destination
      local sim = {
        platform = types.Platform.IOS_SIMULATOR,
        id = "deadbeef-deadbeefdeadbeef",
        name = "iPhone 16 Pro",
      }
      givenProject("project", "testScheme", {}, sim)
      givenTarget("/path/to/build/TestApp.app", "com.test.TestApp")

      stub_external_cmd(0, { "xcrun", "simctl", "boot", sim.id }, "")
      stub_external_cmd(0, { "xcode-select", "-p" }, "/Applications/Xcode-16.2.app/Contents/Developer\n")
      stub_external_cmd(0, { "open", "/Applications/Xcode-16.2.app/Contents/Developer/Applications/Simulator.app" }, "")
      stub_external_cmd({ 149, 0 }, { "xcrun", "simctl", "install", sim.id, "/path/to/build/TestApp.app" }, "")
      stub_external_cmd(0, {
        "xcrun",
        "simctl",
        "launch",
        "--terminate-running-process",
        "--console-pty",
        "--wait-for-debugger",
        sim.id,
        "com.test.TestApp",
      }, "")

      assert.are.same(0, project.debug())

      assert.are.same({
        {
          name = "iOS App Debugger",
          type = "lldb",
          request = "attach",
          program = "/path/to/build/TestApp.app",
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          waitFor = true,
        },
      }, stubbed_dap)
    end)
  end)
end)
