local nio = require("nio")
local assert = require("luassert")
local project = require("project")
local util = require("util")
local sut = require("xcode")
local types = require("types")
local helpers = require("spec/helpers")
local it = nio.tests.it

describe("Build logic", function()
  ---@type table<string, StubbedCommand>
  local stubbed_commands = {}

  before_each(function()
    stubbed_commands = {}
    util.setup({
      run_cmd = helpers.setup_run_cmd(stubbed_commands),
    })
    project.current_project = nil
    ---@diagnostic disable-next-line: duplicate-set-field
    util.get_cwd = function()
      return "/cwd"
    end
  end)

  ---@param code number
  ---@param stubbed_cmd string[]
  ---@param output string
  ---@param use_on_stdout boolean|nil
  local function stub_external_cmd(code, stubbed_cmd, output, use_on_stdout)
    local use = use_on_stdout or false
    stubbed_commands[table.concat(stubbed_cmd, " ")] = { code = code, output = output, use_on_stdout = use }
  end

  ---@param scheme string
  ---@param path? string
  local function givenProject(scheme, path)
    project.current_project = {
      path = path or "/path/project.xcodeproj",
      type = "project",
      schemes = { scheme },
      scheme = scheme,
      destinations = {},
      destination = {
        platform = types.Platform.IOS_DEVICE,
        id = "deadbeef",
        name = "name",
      },
      tests = {},
    }
  end

  after_each(function()
    project.current_project = nil
    project.current_target = nil
    assert.are.same(stubbed_commands, {}, "The following commands where expected to be invoked: " .. vim.inspect(stubbed_commands))
  end)

  local build_settings_json = [[
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

  local buildResults = [[
    {
      "actionTitle" : "Build \"Cantatas\"",
      "analyzerWarningCount" : 0,
      "analyzerWarnings" : [

      ],
      "destination" : {
        "architecture" : "arm64",
        "deviceId" : "AAB6B1B4-9363-4020-A42B-96F2BDC5A3BF",
        "deviceName" : "iPhone 16",
        "modelName" : "iPhone 16",
        "osVersion" : "18.2",
        "platform" : "iOS Simulator"
      },
      "endTime" : 1740948664.642,
      "errorCount" : 1,
      "errors" : [
        {
          "className" : "DVTTextDocumentLocation",
          "issueType" : "Swift Compiler Error",
          "message" : "Cannot find 'name' in scope",
          "sourceURL" : "file:///Users/user/Hello.swift#EndingColumnNumber=8&EndingLineNumber=20&StartingColumnNumber=8&StartingLineNumber=20&Timestamp=762641443.309049"
        }
      ],
      "startTime" : 1740948643.285,
      "status" : "failed",
      "warningCount" : 1,
      "warnings" : [
        {
          "className" : "DVTTextDocumentLocation",
          "issueType" : "Deprecation",
          "message" : "'eraseToStream()' is deprecated: Explicitly wrap this async sequence with 'UncheckedSendable' before erasing to stream.",
          "sourceURL" : "file:///Users/user/World.swift#EndingColumnNumber=21&EndingLineNumber=30&StartingColumnNumber=21&StartingLineNumber=30&Timestamp=762641443.309049"
        },
        {
          "className" : "DVTTextDocumentLocation",
          "issueType" : "Unused ",
          "message" : "value 'data' was defined but never used; consider replacing with boolean test",
          "sourceURL" : "file:///Users/user/Document.swift#EndingColumnNumber=19&EndingLineNumber=15&StartingColumnNumber=19&StartingLineNumber=15&Timestamp=762641443.309049"
        }
      ]
    }
  ]]
  local function given_remove_build_result()
    stub_external_cmd(0, { "rm", "-rf", "/cwd/.neoxcd/build.xcresult" }, "")
  end

  ---@param result? string
  local function given_build_settings(result)
    stub_external_cmd(0, {
      "xcodebuild",
      "build",
      "-scheme",
      project.current_project.scheme,
      "-showBuildSettings",
      "-json",
      "-destination",
      "id=" .. project.current_project.destination.id,
    }, result or build_settings_json)
  end

  ---@param results? string
  local function given_results(results)
    -- xcrun xcresulttool get build-results --pparses logs without build errorsath results.xcresult
    stub_external_cmd(0, {
      "xcrun",
      "xcresulttool",
      "get",
      "build-results",
      "--path",
      "/cwd/.neoxcd/build.xcresult",
    }, results or buildResults)
  end

  it("parses logs without build errors", function()
    givenProject("scheme", "/not/overwritten/project/project.xcodeproj")

    given_remove_build_result()
    given_build_settings(build_settings_json)
    stub_external_cmd(0, {
      "xcodebuild",
      "build",
      "-scheme",
      "scheme",
      "-destination",
      "id=" .. project.current_project.destination.id,
      "-configuration",
      "Debug",
      "-resultBundlePath",
      "/cwd/.neoxcd/build.xcresult",
      "-project",
      project.current_project.path,
    }, "")
    given_results(buildResults)

    ---@type QuickfixEntry[]
    local expected = {
      {
        filename = "/Users/user/Hello.swift",
        lnum = 21, --- indices are 1-based
        col = 9,
        type = "E",
        text = "Cannot find 'name' in scope",
      },
      {
        filename = "/Users/user/World.swift",
        lnum = 31,
        col = 22,
        type = "W",
        text = "'eraseToStream()' is deprecated: Explicitly wrap this async sequence with 'UncheckedSendable' before erasing to stream.",
      },
      {
        filename = "/Users/user/Document.swift",
        lnum = 16,
        col = 20,
        type = "W",
        text = "value 'data' was defined but never used; consider replacing with boolean test",
      },
    }

    assert.are.same(project.ProjectResult.SUCCESS, sut.build())
    assert.are.same(expected, project.current_project.quickfixes)
    assert.are.same("/not/overwritten/project/project.xcodeproj", project.current_project.path)
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

  it("Parses the project settings", function()
    givenProject("scheme", "/not/overwritten/project/project.xcodeproj")

    given_build_settings(build_settings_json)

    assert.are.same(0, sut.load_build_settings())
    assert.are.same("/not/overwritten/project/project.xcodeproj", project.current_project.path)
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
    project.current_project.build_settings = {}
    project.current_project.quickfixes = {}
    project.current_target = {
      name = "MyProduct",
      app_path = "/path/to/app",
      bundle_id = "com.product.myproduct",
      plist = "/path/to/plist",
      module_name = "MyProduct",
    }
    stub_external_cmd(
      0,
      { "xcodebuild", "clean", "-scheme", "scheme", "-destination", "id=deadbeef", "-project", "/path/project.xcodeproj" },
      ""
    )
    assert.are.same(0, sut.clean())
    assert.is_nil(project.current_project.quickfixes)
    assert.is_nil(project.current_project.build_settings)
    assert.is_nil(project.current_target)
  end)

  it("Can build for testing", function()
    givenProject("scheme")

    given_remove_build_result()
    given_build_settings(build_settings_json)
    stub_external_cmd(0, {
      "xcodebuild",
      "build-for-testing",
      "-scheme",
      "scheme",
      "-destination",
      "id=" .. project.current_project.destination.id,
      "-configuration",
      "Debug",
      "-resultBundlePath",
      "/cwd/.neoxcd/build.xcresult",
      "-project",
      "/path/project.xcodeproj",
    }, "")
    given_results(buildResults)

    assert.are.same(project.ProjectResult.SUCCESS, sut.build(true))
  end)
end)
