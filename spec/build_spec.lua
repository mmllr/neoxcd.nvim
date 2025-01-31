local nio = require("nio")
local project = require("project")

local it = nio.tests.it
---@param scheme string
local function givenProject(scheme)
  project.current_project = {
    path = "",
    type = "project",
    schemes = { scheme },
    destinations = {},
  }
  project.current_project.scheme = scheme
  project.current_project.destination = {
    platform = "iOS",
    id = "id",
    name = "name",
  }
end

describe("Build logic", function()
  it("parses logs without build errors", function()
    local logs = [[
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
/Users/user/Document.swift:15:19: warning: value 'data' was defined but never used; consider replacing with boolean test
        guard let data = configuration.file.regularFileContents
              ~~~~^~~~~~~
                                                                != nil
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
/Users/user/View.swift:21:20: error: value 'destination' was defined but never used; consider replacing with boolean test
            if let destination = store.scope(state: \.destination?, action: \.destination.presented) {
               ~~~~^~~~~~~~~~~~~~
                                                                                                     != nil
/Users/user/Feature.swift:144:41: warning: immutable value 'sectionID' was never used; consider replacing with '_' or removing it
            case let .sections(.element(sectionID, .rows(.element(bookID, .tapped)))):
                                        ^~~~~~~~~
                                        _
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
note: Run script build phase 'Build number from git' will be run during every build because the option to run the script phase "Based on dependency analysis" is unchecked. (in target 'CantatasEditor' from project 'Cantatas')
      ]]

    ---@type QuickfixEntry[]
    local expected = {
      {
        filename = "/Users/user/Document.swift",
        lnum = 15,
        col = 19,
        type = "W",
        text = "value 'data' was defined but never used; consider replacing with boolean test",
      },
      {
        filename = "/Users/user/View.swift",
        lnum = 21,
        col = 20,
        text = "value 'destination' was defined but never used; consider replacing with boolean test",
        type = "E",
      },
      {
        filename = "/Users/user/Feature.swift",
        lnum = 144,
        col = 41,
        text = "immutable value 'sectionID' was never used; consider replacing with '_' or removing it",
        type = "W",
      },
    }

    assert.are.same(expected, require("xcode").parse_quickfix_list(logs))
  end)

  it("Parses the project settings", function()
    local util = require("util")
    local sut = require("xcode")
    givenProject("scheme")
    local log = [[
    export PRODUCT_BUNDLE_IDENTIFIER\=com.product.myproduct
    export PRODUCT_BUNDLE_PACKAGE_TYPE\=APPL
    export PRODUCT_MODULE_NAME\=MyProduct-Folder
    export PRODUCT_NAME\=MyProduct
    export PRODUCT_SETTINGS_PATH\=/Users/user/MyProject-Folder/MyProduct/Info.plist
    export PRODUCT_TYPE\=com.apple.product-type.application
    export PROFILING_CODE\=NO
    export PROJECT\=MyProject
    export PROJECT_DERIVED_FILE_DIR\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex/MyProject.build/DerivedSources
    export PROJECT_DIR\=/Users/user/MyProject
    export PROJECT_FILE_PATH\=/Users/user/MyProject/MyProject.xcodeproj
    export PROJECT_GUID\=ad98a1d3d4fc98c1821c175190d3f
    export PROJECT_NAME\=MyProject
    export PROJECT_TEMP_DIR\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex/MyProject.build
    export PROJECT_TEMP_ROOT\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex
      ]]

    local invoked_cmd = {}
    --- @diagnostic disable-next-line: duplicate-set-field
    util.run_job = function(cmd, on_exit, on_stdout)
      invoked_cmd = cmd
      for line in string.gmatch(log, "[^\r\n]+") do
        if on_stdout then
          on_stdout(nil, line)
        end
      end
      on_exit({
        signal = 0,
        code = 0,
      })
    end

    assert.are.same(0, sut.build())
    assert.are.same(
      { "xcodebuild", "build", "-scheme", "scheme", "-destination", "platform=iOS,id=id", "-configuration", "Debug" },
      invoked_cmd
    )
    assert.are.same("/Users/user/MyProject/MyProject.xcodeproj", project.current_project.path)
    assert.are.same("MyProject", project.current_project.name)
    assert.are.same("MyProduct", project.current_target.name)
    assert.are.same("com.product.myproduct", project.current_target.bundle_id)
    assert.are.same("/Users/user/MyProject-Folder/MyProduct/Info.plist", project.current_target.plist)
    assert.are.same("MyProduct-Folder", project.current_target.module_name)
  end)
end)
