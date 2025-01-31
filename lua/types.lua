---A class representing a destination for a build.
---@class Destination
---@field platform string
---@field arch? string
---@field variant? string
---@field id string
---@field name string
---@field OS? string

---A class representing a vim quickfix entry
---@class QuickfixEntry
---@field filename string
---@field lnum number
---@field col number
---@field text string
---@field type string "W" | "E

---An enum describing a project
---@alias ProjectType "project" | "workspace" | "package"

---A class representing a Xcode project
---@class Project
---@field name? string
---@field path string
---@field type ProjectType
---@field scheme? string
---@field destination? Destination
---@field schemes string[]
---@field destinations Destination[]
---@field quickfixes? QuickfixEntry[]

---A class representing a build target
---@class Target
---@field name string
---@field bundle_id string
---@field plist string
---@field module_name string
