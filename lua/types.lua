local M = {}

---Platform type enum.
---These values match constants emitted by `xcodebuild` commands.
---@alias Platform
---| 'iOS' # physical iOS device (iPhone or iPad)
---| 'iOS Simulator' # iOS simulator (iPhone or iPad)
---| 'tvOS Simulator' # tvOS simulator (Apple TV)
---| 'tvOS' # tvOS device (Apple TV)
---| 'watchOS Simulator' # watchOS simulator (Apple Watch)
---| 'watchOS' # watchOS device (Apple Watch)
---| 'visionOS Simulator' # visionOS simulator (Apple Glasses)
---| 'visionOS' # visionOS device (Apple Glasses)
---| 'macOS' # macOS
---| 'DriverKit'

---Platform constants.
---@class PlatformConstants
---@field IOS_DEVICE Platform physical iOS device (iPhone or iPad)
---@field IOS_SIMULATOR Platform iOS simulator (iPhone or iPad)
---@field TVOS_SIMULATOR Platform tvOS simulator (Apple TV)
---@field TVOS_DEVICE Platform tvOS device (Apple TV)
---@field WATCHOS_SIMULATOR Platform watchOS simulator (Apple Watch)
---@field WATCHOS_DEVICE Platform watchOS device (Apple Watch)
---@field VISIONOS_SIMULATOR Platform visionOS simulator (Apple Glasses)
---@field VISIONOS_DEVICE Platform visionOS device (Apple Glasses)
---@field MACOS Platform macOS

---Platform type enum.
---@type PlatformConstants
M.Platform = {
  IOS_DEVICE = "iOS",
  IOS_SIMULATOR = "iOS Simulator",
  TVOS_SIMULATOR = "tvOS Simulator",
  TVOS_DEVICE = "tvOS",
  WATCHOS_SIMULATOR = "watchOS Simulator",
  WATCHOS_DEVICE = "watchOS",
  VISIONOS_SIMULATOR = "visionOS Simulator",
  VISIONOS_DEVICE = "visionOS",
  MACOS = "macOS",
}

---Architecture enum.
---@alias Architecture
---| 'arm64e' # arm64e
---| 'arm64' # arm64
---| 'x86_64' # x86_64

---Architecture constants.
---@class ArchitectureConstants
---@field ARM64E Architecture arm64e
---@field ARM64 Architecture arm64
---@field X86_64 Architecture x86_64

---@type ArchitectureConstants
M.Architecture = {
  ARM64E = "arm64e",
  ARM64 = "arm64",
  X86_64 = "x86_64",
}

---A class representing a destination for a build.
---@class Destination
---@field platform Platform
---@field arch? Architecture
---@field variant? string
---@field id? string
---@field name string
---@field OS? string

---The type of a quickfix entry.
---@alias QuickfixEntryType
---| "W"
---| "E"

---@class QuickfixEntryTypeConstants
---@field WARNING QuickfixEntryType
---@field ERROR QuickfixEntryType

---@type QuickfixEntryTypeConstants
M.QuickfixEntryType = {
  WARNING = "W",
  ERROR = "E",
}

---A class representing a vim quickfix entry
---@class QuickfixEntry
---@field filename string
---@field lnum number
---@field col number
---@field text string
---@field type QuickfixEntryType

---An enum describing a project
---@alias ProjectType
---| "project" A Xcode project
---| "workspace" A Xcode workspace
---| "package" A Swift package

---@class ProjectConstants
---@field SWIFT_PACKAGE ProjectType
---@field XCODE_PROJECT ProjectType
---@field XCODE_WORKSPACE ProjectType

---@type ProjectConstants
M.ProjectConstants = {
  SWIFT_PACKAGE = "package",
  XCODE_PROJECT = "project",
  XCODE_WORKSPACE = "workspace",
}

---A cached entry for mapping destinations to schemes
---@alias DestinationCache table<string, Destination[]>

---A class representing a Xcode project
---@class Project
---@field name? string
---@field path string
---@field type ProjectType
---@field scheme? string
---@field destination? Destination
---@field schemes string[]
---@field quickfixes? QuickfixEntry[]
---@field build_settings? table<string, string>
---@field test_results? TestNode[]

---A class representing a build target
---@class Target
---@field name string
---@field bundle_id string
---@field plist string
---@field module_name string
---@field app_path string

---A Test TestEnumerationType
---@alias TestEnumerationKind "plan" | "target" | "class" | "test"

---A class representing a test case
---@class TestEnumeration
---@field children TestEnumeration[]
---@field disabled boolean
---@field kind TestEnumerationKind
---@field name string

---A test node kind
---@alias TestNodeType
---| "Test Plan"
---| "Test Case"
---| "Test Suite"
---| "Arguments"
---| "Unit test bundle"
---| "Failure Message"
---| "UI test bundle"
---| "Device"
---| "Test Plan Configuration"
---| "Arguments"
---| "Repetition"
---| "Test Case Run"
---| "Source Code Reference"
---| "Attachment"
---| "Expression"
---| "Test Value"

---The result for a test node
---@alias TestNodeResult
---| "Failed"
---| "Passed"
---| "Skipped"
---| "Expected Failure"
---| "unknown"

---A node for a runned test
---@class TestNode
---@field name string
---@field nodeType TestNodeType
---@field result? TestNodeResult
---@field nodeIdentifierURL? string
---@field nodeIdentifier? string
---@field duration? string
---@field details? string
---@field children? TestNode[]

return M
