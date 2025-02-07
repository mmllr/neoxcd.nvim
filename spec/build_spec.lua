local nio = require("nio")
local assert = require("luassert")
local project = require("project")
local util = require("util")
local sut = require("xcode")
local types = require("types")
local it = nio.tests.it

describe("Build logic", function()
  local invoked_cmd
  ---@param code number|nil
  ---@param output string
  local function stub_run_job(code, output)
    --- @diagnostic disable-next-line: duplicate-set-field
    util.run_job = function(cmd, on_stdout, on_exit)
      invoked_cmd = cmd
      for line in string.gmatch(output, "[^\r\n]+") do
        if on_stdout then
          on_stdout(nil, line)
        end
      end
      on_exit({
        signal = 0,
        code = code or 0,
        stdout = output,
      })
    end
  end

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
      platform = types.Platform.IOS_DEVICE,
      id = "id",
      name = "name",
    }
  end

  before_each(function()
    invoked_cmd = nil
    project.current_project = nil
  end)

  it("parses logs without build errors", function()
    givenProject("scheme")
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

    stub_run_job(0, logs)
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

    assert.are.same(0, sut.build())
    assert.are.same(expected, project.current_project.quickfixes)
  end)

  it("Parses the project settings", function()
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
    export TARGET_BUILD_DIR\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Products/Debug-iphonesimulator
    export WRAPPER_NAME\=MyProduct.app
    export FULL_PRODUCT_NAME\=MyProduct.app
      ]]

    stub_run_job(0, log)

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
    assert.are.same(
      "/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Products/Debug-iphonesimulator/MyProduct.app",
      project.current_target.app_path
    )
  end)

  it("Clean command", function()
    givenProject("scheme")
    stub_run_job(0, "")
    assert.are.same(0, sut.clean())
    assert.are.same({ "xcodebuild", "clean", "-scheme", "scheme", "-destination", "platform=iOS,id=id" }, invoked_cmd)
  end)
end)
