import Foundation
import XCTest

@testable import DescriberCore

/// Reading every key of `settings.json` into `AppSettings` (spec 3 and 12), and the errors for values the app can't
/// use.
final class SettingsTests: XCTestCase {
    private func read(_ text: String) throws -> AppSettings {
        try SettingsFile.settings(in: Data(text.utf8))
    }

    private func error(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        do {
            _ = try read(text)
            XCTFail("“\(text)” read without an error", file: file, line: line)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    func testAFileWithEveryKeyReadsEveryValue() throws {
        let settings = try read(
            """
            {
              "defaultViewport": "ipad",
              "gridSize": 16,
              "snapping": false,
              "viewportPresets": [{ "name": "Watch", "width": 198, "height": 242 }],
              "keybinds": { "regionTool": "b", "zoomIn": ["cmd-+", "cmd-="], "followLink": [] }
            }
            """)
        XCTAssertEqual(settings.defaultViewport, .viewport(Viewport(preset: "ipad", width: 820, height: 1180)))
        XCTAssertEqual(settings.gridSize, 16)
        XCTAssertFalse(settings.snapping)
        XCTAssertEqual(settings.viewportPresets, [ViewportPreset(id: "watch", name: "Watch", width: 198, height: 242)])
        XCTAssertEqual(
            settings.keybindOverrides,
            [
                .regionTool: [KeyCombo("b")], .zoomIn: [KeyCombo("+", .command), KeyCombo("=", .command)],
                .followLink: [],
            ])
    }

    func testAMissingOrBlankFileIsTheDefaults() throws {
        XCTAssertEqual(try SettingsFile.settings(in: nil), .defaults)
        XCTAssertEqual(try read(" \n"), .defaults)
        XCTAssertEqual(try read("{}"), .defaults)
        let defaults = AppSettings.defaults
        XCTAssertEqual(defaults.defaultViewport, .viewport(.defaultForNewScreens))
        XCTAssertEqual(defaults.gridSize, 8)
        XCTAssertTrue(defaults.snapping)
        XCTAssertEqual(defaults.keybinds.combos(for: .regionTool), [KeyCombo("r")])
    }

    func testTheDefaultViewportCanNameAnyKindOfViewport() throws {
        XCTAssertEqual(
            try read(#"{"defaultViewport": "iPhone SE"}"#).defaultViewport,
            .viewport(Viewport(preset: "iphone-se", width: 375, height: 667)), "a built-in preset by name")
        XCTAssertEqual(try read(#"{"defaultViewport": "this-device"}"#).defaultViewport, .thisDevice)
        XCTAssertEqual(
            try read(#"{"defaultViewport": {"width": 500, "height": 400}}"#).defaultViewport,
            .viewport(Viewport(width: 500, height: 400)))
        let user = try read(
            #"{"defaultViewport": "my watch", "viewportPresets": [{"name": "My Watch", "width": 198, "height": 242}]}"#)
        XCTAssertEqual(
            user.defaultViewport, .viewport(Viewport(preset: "my-watch", width: 198, height: 242)),
            "a user preset by name, with its ID")
        XCTAssertEqual(
            try read(#"{"defaultViewport": "laptop"}"#).newScreenViewport(displaySize: (1512, 982)),
            Viewport(preset: "laptop", width: 1440, height: 900))
    }

    func testThisDeviceIsMeasuredFromTheDisplay() throws {
        let settings = try read(#"{"defaultViewport": "this-device"}"#)
        XCTAssertEqual(
            settings.newScreenViewport(displaySize: (1512, 982.4)),
            Viewport(preset: ViewportPresets.thisDeviceID, width: 1512, height: 982))
        XCTAssertEqual(settings.newScreenViewport(displaySize: nil), .defaultForNewScreens)
    }

    func testEachBadValueIsAnErrorNamingItsKey() {
        let cases: [(String, String)] = [
            ("{ oops", "settings.json: line 1: Expected a key in quotes."),
            ("[]", "settings.json: the file should hold one JSON object, in { }."),
            (
                #"{"gridsize": 8}"#,
                "settings.json: “gridsize” isn’t a setting. The settings are “defaultViewport”, “gridSize”, "
                    + "“snapping”, “viewportPresets” and “keybinds”."
            ),
            (#"{"gridSize": 8, "gridSize": 16}"#, "settings.json: “gridSize” appears more than once."),
            (#"{"gridSize": 10}"#, "settings.json: “gridSize” should be one of 4, 8, 12, 16, 24 or 32."),
            (#"{"gridSize": "8"}"#, "settings.json: “gridSize” should be one of 4, 8, 12, 16, 24 or 32."),
            (#"{"snapping": "yes"}"#, "settings.json: “snapping” should be true or false."),
            (
                #"{"defaultViewport": "Pixel"}"#,
                "settings.json: “defaultViewport” names “Pixel”, which isn’t a viewport preset. Use a preset’s "
                    + "name, “this-device”, or { \"width\": …, \"height\": … }."
            ),
            (
                #"{"defaultViewport": {"width": 0, "height": 400}}"#,
                "settings.json: “defaultViewport” needs a width and height of at least 1 point, such as "
                    + "{ \"width\": 500, \"height\": 400 }."
            ),
            (
                #"{"defaultViewport": 5}"#,
                "settings.json: “defaultViewport” should be a preset’s name, “this-device”, or "
                    + "{ \"width\": …, \"height\": … }."
            ),
            (
                #"{"viewportPresets": [{"name": "A", "width": 0, "height": 5}]}"#,
                "settings.json: viewportPresets[0] needs a name, and a width and height of at least 1 point."
            ),
            (
                #"{"keybinds": ["v"]}"#,
                "settings.json: “keybinds” should map action names to keys, such as { \"regionTool\": \"b\" }."
            ),
            (
                #"{"keybinds": {"rectangleTool": "b"}}"#,
                "settings.json: keybinds: “rectangleTool” isn’t an action. The actions are listed in "
                    + "Schema/README.md."
            ),
            (
                #"{"keybinds": {"regionTool": 5}}"#,
                "settings.json: keybinds.regionTool should be a key, such as \"shift-d\", or a list of keys."
            ),
            (
                #"{"keybinds": {"regionTool": "hyper-b"}}"#,
                "settings.json: keybinds.regionTool has “hyper-b”, which isn’t a key. Keys look like “v”, "
                    + "“shift-d” or “cmd-option-left”."
            ),
            (
                #"{"keybinds": {"regionTool": "b", "writeTool": ["x", "b"]}}"#,
                "settings.json: keybinds gives “b” to both “regionTool” and “writeTool”."
            ),
        ]
        for (text, message) in cases {
            XCTAssertEqual(error(text), message, text)
        }
    }

    func testKeybindOverridesReachTheRegistry() throws {
        let keybinds = try read(
            #"{"keybinds": {"regionTool": "b", "followLink": [], "selectTool": "r", "zoomIn": ["cmd-+", "cmd-="]}}"#
        ).keybinds
        XCTAssertEqual(keybinds.action(for: KeyCombo("b")), .regionTool)
        XCTAssertEqual(keybinds.combos(for: .regionTool), [KeyCombo("b")], "a list replaces the defaults")
        XCTAssertEqual(keybinds.action(for: KeyCombo("r")), .selectTool, "R moved to the Select tool")
        XCTAssertNil(keybinds.action(for: KeyCombo("v")), "V lost the Select tool to the override")
        XCTAssertEqual(keybinds.combos(for: .followLink), [], "an empty list unbinds")
        XCTAssertNil(keybinds.action(for: KeyCombo("l")))
        XCTAssertEqual(keybinds.combos(for: .writeTool), [KeyCombo("w")], "actions without overrides keep defaults")
    }

    func testSettingsComparedByValue() throws {
        let file = #"{"keybinds": {"regionTool": "b"}, "gridSize": 16}"#
        XCTAssertEqual(try read(file), try read(file))
        XCTAssertNotEqual(try read(file), try read(#"{"keybinds": {"regionTool": "c"}, "gridSize": 16}"#))
        XCTAssertNotEqual(try read(file), .defaults)
    }

    func testOnlyTheViewportPresetsAreCheckedWhenReadingThemAlone() throws {
        // Saving a preset checks the whole file first (`SettingsStore`); this reader looks at one key.
        XCTAssertEqual(
            try SettingsFile.viewportPresets(in: Data(#"{"gridSize": 10, "viewportPresets": []}"#.utf8)), [])
        XCTAssertThrowsError(try SettingsFile.settings(in: Data(#"{"gridSize": 10, "viewportPresets": []}"#.utf8)))
    }
}

extension SettingsTests {
    func testSavingAPresetKeepsTheOtherSettings() throws {
        let file = Data(#"{"gridSize": 16, "viewportPresets": [{"name": "Watch", "width": 1, "height": 1}]}"#.utf8)
        let saved = try SettingsFile.savingViewportPreset(name: "watch", width: 198, height: 242, in: file)
        XCTAssertEqual(saved.preset, ViewportPreset(id: "watch", name: "watch", width: 198, height: 242))
        XCTAssertEqual(saved.settings.gridSize, 16)
        XCTAssertEqual(saved.settings.viewportPresets, [saved.preset])
        XCTAssertEqual(try SettingsFile.settings(in: saved.data), saved.settings)
        XCTAssertTrue(String(decoding: saved.data, as: UTF8.self).hasPrefix("{\n  \"gridSize\": 16,"))
    }

    func testAFileWithABadValueIsNeverRewrittenBySavingAPreset() {
        for bad in [#"{"keybinds": {"regionTool": "hyper-b"}}"#, #"{"gridSize": 10}"#, "{ oops"] {
            XCTAssertThrowsError(
                try SettingsFile.savingViewportPreset(name: "Watch", width: 198, height: 242, in: Data(bad.utf8)), bad)
        }
    }
}

extension SettingsTests {
    /// Errors for unknown actions point at `Schema/README.md`, so it names every one.
    func testTheSchemaReadmeListsEverySettingAndAction() throws {
        let readme = try String(
            contentsOf: Fixtures.repositoryRoot.appendingPathComponent("Schema/README.md"), encoding: .utf8)
        for name in SettingsFile.keys + KeyAction.allCases.map(\.rawValue) {
            XCTAssertTrue(readme.contains("`\(name)`"), "Schema/README.md doesn't name `\(name)`")
        }
    }
}
