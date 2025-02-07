local nio = require("nio")
local assert = require("luassert")
local project = require("project")
local util = require("util")
local sut = require("xcode")
local types = require("types")
local it = nio.tests.it

describe("Build logic", function()
  ---@type table<string, StubbedCommand>
  local stubbed_commands = {}
  local previous_run_job

  ---@param code number|nil
  ---@param output string
  local function stub_run_job(code, output)
    if not previous_run_job then
      previous_run_job = util.run_job
    end
    --- @diagnostic disable-next-line: duplicate-set-field
    util.run_job = function(cmd, on_stdout, on_exit)
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

  ---@param code number
  ---@param stubbed_cmd string[]
  ---@param output string
  local function stub_external_cmd(code, stubbed_cmd, output)
    if not previous_run_job then
      previous_run_job = util.run_job
    end
    stubbed_commands[table.concat(stubbed_cmd, " ")] = { code = code, output = output }
    --- @diagnostic disable-next-line: duplicate-set-field
    util.run_job = function(cmd, _, on_exit)
      local key = table.concat(cmd, " ")
      on_exit({
        signal = 0,
        stdout = stubbed_commands[key].output,
        code = stubbed_commands[key].code,
      })
      stubbed_commands[key] = nil
    end
  end

  ---@param scheme string
  local function givenProject(scheme)
    project.current_project = {
      path = "",
      type = "project",
      schemes = { scheme },
      scheme = scheme,
      destinations = {},
      destination = {
        platform = types.Platform.IOS_DEVICE,
        id = "id",
        name = "name",
      },
    }
  end

  teardown(function()
    if previous_run_job then
      util.run_job = previous_run_job
    end
    previous_run_job = nil
  end)

  before_each(function()
    invoked_cmd = nil
    project.current_project = nil
  end)

  after_each(function()
    project.current_project = nil
    project.current_target = nil
    assert.are.same(
      stubbed_commands,
      {},
      "The following commands where expected to be invoked: " .. vim.inspect(stubbed_commands)
    )
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
    local json = [[
[
  {
    "action" : "build",
    "buildSettings" : {
      "PRODUCT_BUNDLE_IDENTIFIER" : "com.product.myproduct",
      "PRODUCT_BUNDLE_PACKAGE_TYPE" : "APPL",
      "PRODUCT_MODULE_NAME" : "MyProduct-Folder",
      "PRODUCT_NAME" : "MyProduct",
      "PRODUCT_SETTINGS_PATH" : "/Users/user/MyProject-Folder/MyProduct/Info.plist",
      "PRODUCT_TYPE" : "com.apple.product-type.application",
      "PROFILING_CODE" : "NO",
      "PROJECT" : "MyProject",
      "PROJECT_DERIVED_FILE_DIR" : "/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex/MyProject.build/DerivedSources",
      "PROJECT_DIR" : "/Users/user/MyProject",
      "PROJECT_FILE_PATH" : "/Users/user/MyProject/MyProject.xcodeproj",
      "PROJECT_GUID" : "ad98a1d3d4fc98c1821c175190d3f",
      "PROJECT_NAME" : "MyProject",
      "PROJECT_TEMP_DIR" : "/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex/MyProject.build",
      "PROJECT_TEMP_ROOT" : "/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex",
      "TARGET_BUILD_DIR" : "/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Products/Debug-iphonesimulator",
      "WRAPPER_NAME" : "MyProduct.app",
      "FULL_PRODUCT_NAME" : "MyProduct.app"
    },
    "target" : "MyProduct"
  }
]
      ]]

    stub_external_cmd(0, {
      "xcodebuild",
      "build",
      "-scheme",
      "scheme",
      "-destination",
      "platform=iOS,id=id",
      "-configuration",
      "Debug",
      "-showBuildSettings",
      "-json",
    }, json)

    assert.are.same(0, sut.load_build_settings())
    -- assert.are.same({}, project.current_project.build_settings)
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
    stub_external_cmd(0, { "xcodebuild", "clean", "-scheme", "scheme", "-destination", "platform=iOS,id=id" }, "")
    assert.are.same(0, sut.clean())
  end)
end)
