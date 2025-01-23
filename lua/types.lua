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

---A class representing a project
---@class Project
---@field path string
---@field type ProjectType
