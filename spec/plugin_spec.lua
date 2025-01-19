describe("Scheme parsing", function()
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
    local util = require("util")
    assert.are.same(expected, util.parse_schemes(json))
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
    local expexted = {
      "SchemeA",
      "SchemeB",
    }

    local util = require("util")
    assert.are.same(expexted, util.parse_schemes(json))
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
    assert.are.same(expected, require("util").parse_destinations(output))
  end)
end)

describe("Destination format for UI", function()
  --@type Destination
  local destination
  it("Format a mac", function()
    destination = { name = "My Mac", platform = "macOS", arch = "arm64" }
    assert.are.equal("󰇄 My Mac", require("util").format_destination(destination))
  end)

  it("Format a mac with variant", function()
    destination = { name = "My Mac", platform = "macOS", variant = "Mac Catalyst" }
    assert.are.equal("󰇄 My Mac (Mac Catalyst)", require("util").format_destination(destination))
  end)

  it("Formats a tvOS", function()
    destination = { name = "Any tvOS Device", platform = "tvOS" }
    assert.are.equal(" Any tvOS Device", require("util").format_destination(destination))
  end)

  it("Formats a watchOS", function()
    destination = { name = "Any watchOS Device", platform = "watchOS" }
    assert.are.equal("󰢗 Any watchOS Device", require("util").format_destination(destination))
  end)

  it("Formats any simulator", function()
    destination = { name = "Any iOS Simulator Device", platform = "iOS Simulator" }
    assert.are.equal("󰦧 Any iOS Simulator Device", require("util").format_destination(destination))
  end)

  it("Formats a phone specific simulator", function()
    destination = { name = "iPhone 6s", platform = "iOS Simulator", OS = "15.5" }
    assert.are.equal(" iPhone 6s (15.5)", require("util").format_destination(destination))
  end)

  it("Formats a tablet specific simulator", function()
    destination = { name = "iPad Air", platform = "iOS Simulator", OS = "18.2" }
    assert.are.equal("󰓶 iPad Air (18.2)", require("util").format_destination(destination))
  end)

  it("Formats a DriverKit platform", function()
    destination = { name = "Any DriverKit Host", platform = "DriverKit" }
    assert.are.equal("󰇄 Any DriverKit Host", require("util").format_destination(destination))
  end)
end)
