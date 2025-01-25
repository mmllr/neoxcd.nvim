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
    export PROJECT_GUID\=679ad98a1d3d4fc98c1821c175190d3f
    export PROJECT_NAME\=MyProject
    export PROJECT_TEMP_DIR\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex/MyProject.build
    export PROJECT_TEMP_ROOT\=/Users/user/Library/Developer/Xcode/DerivedData/MyProject-ajwpsjchvdfqfzgtlxruzmeqaxwl/Build/Intermediates.noindex
      ]]

    ---@type Target
    local expected = {
      name = "MyProduct",
      bundle_id = "com.product.myproduct",
      module_name = "MyProduct-Folder",
      plist = "/Users/user/MyProject-Folder/MyProduct/Info.plist",
      project = {
        name = "MyProject",
        path = "/Users/user/MyProject/MyProject.xcodeproj",
        type = "project",
      },
    }
    assert.are.same(expected, require("xcode").parse_build_output(log))
  end)
end)
