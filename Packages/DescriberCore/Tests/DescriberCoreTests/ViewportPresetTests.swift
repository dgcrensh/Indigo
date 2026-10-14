import XCTest

@testable import DescriberCore

/// Viewport presets (spec 8.2), the order-keeping JSON reader, and user presets in `settings.json`.
final class ViewportPresetTests: XCTestCase {
    func testLabelsNameEveryKindOfViewport() {
        let watch = ViewportPresets.userPresets([(name: "My Watch", width: 198, height: 242)])
        XCTAssertEqual(watch.map(\.id), ["my-watch"])
        XCTAssertEqual(
            ViewportPresets.label(for: Viewport(preset: "iphone-15", width: 393, height: 852)), "iPhone 15 — 393 × 852")
        XCTAssertEqual(
            ViewportPresets.label(for: ViewportPresets.thisDevice(width: 1512, height: 982.4)),
            "This Device — 1512 × 982")
        XCTAssertEqual(ViewportPresets.label(for: Viewport(width: 500, height: 400)), "Custom — 500 × 400")
        XCTAssertEqual(
            ViewportPresets.label(for: watch[0].viewport, userPresets: watch), "My Watch — 198 × 242")
        XCTAssertEqual(
            ViewportPresets.label(for: Viewport(preset: "elsewhere", width: 10, height: 20)), "elsewhere — 10 × 20")
    }

    func testTheNewDocumentPresetIsBuiltIn() {
        XCTAssertEqual(ViewportPresets.preset(withID: "iphone-15")?.viewport, .defaultForNewScreens)
        XCTAssertEqual(Set(ViewportPresets.builtIn.map(\.id)).count, ViewportPresets.builtIn.count)
    }

    func testUserPresetIDsAvoidBuiltInsAndEachOther() {
        let presets = ViewportPresets.userPresets([
            (name: "iPhone 15", width: 1, height: 1), (name: "Kiosk", width: 2, height: 2),
            (name: "kiosk!", width: 3, height: 3), (name: "This Device", width: 4, height: 4),
        ])
        XCTAssertEqual(presets.map(\.id), ["iphone-15-2", "kiosk", "kiosk-2", "this-device-2"])
    }

    func testSavingAPresetWithANameInUseChangesItsSize() {
        var presets = ViewportPresets.saving(name: "Kiosk", width: 800, height: 600, in: [])
        presets = ViewportPresets.saving(name: "Watch", width: 198, height: 242, in: presets)
        presets = ViewportPresets.saving(name: "kiosk", width: 1024, height: 768, in: presets)
        XCTAssertEqual(
            presets,
            [
                ViewportPreset(id: "kiosk", name: "kiosk", width: 1024, height: 768),
                ViewportPreset(id: "watch", name: "Watch", width: 198, height: 242),
            ])
    }

    // MARK: JSON reader

    func testTheReaderKeepsKeyOrderAndValues() throws {
        let text = #"{"b": [1, -2.5, 3e2, true, null], "a": {"z": "q\"\né😀", "y": {}}, "c": []}"#
        let value = try JSONReader.parse(Data(text.utf8))
        XCTAssertEqual(
            value,
            .object([
                ("b", .array([.int(1), .double(-2.5), .double(300), .bool(true), .null])),
                ("a", .object([("z", .string("q\"\né😀")), ("y", .object([]))])),
                ("c", .array([])),
            ]))
    }

    func testTheReaderReportsTheLineOfAnError() {
        let text = "{\n  \"a\": 1,\n  \"b\": tru\n}"
        XCTAssertThrowsError(try JSONReader.parse(Data(text.utf8))) { error in
            XCTAssertEqual((error as? JSONReader.ParseError)?.line, 3)
        }
        for bad in ["", "{", "[1,]", "{\"a\" 1}", "01", "\"tab\there\"", "{} {}", "{\"a\":1,}"] {
            XCTAssertThrowsError(try JSONReader.parse(Data(bad.utf8)), bad)
        }
    }

    func testTheReaderMatchesTheWriter() throws {
        let tree = try Fixtures.readTree(at: Fixtures.examplePackage)
        for (path, data) in tree {
            XCTAssertEqual(OrderedJSONWriter.data(try JSONReader.parse(data)), data, path)
        }
    }

    // MARK: Settings file

    func testSavingPresetsKeepsTheOtherSettingsInOrder() throws {
        let file = """
            {
              "keybinds": { "selectTool": "x" },
              "viewportPresets": [],
              "defaultGridSize": 8
            }
            """
        let presets = ViewportPresets.saving(name: "Watch", width: 198, height: 242, in: [])
        let written = try SettingsFile.replacingViewportPresets(presets, in: Data(file.utf8))
        XCTAssertEqual(
            String(decoding: written, as: UTF8.self),
            """
            {
              "keybinds": {
                "selectTool": "x"
              },
              "viewportPresets": [
                {
                  "name": "Watch",
                  "width": 198,
                  "height": 242
                }
              ],
              "defaultGridSize": 8
            }

            """)
        XCTAssertEqual(try SettingsFile.viewportPresets(in: written), presets)
    }

    func testAMissingOrEmptyFileHasNoPresetsAndStartsFromAnEmptyObject() throws {
        XCTAssertEqual(try SettingsFile.viewportPresets(in: nil), [])
        XCTAssertEqual(try SettingsFile.viewportPresets(in: Data(" \n".utf8)), [])
        let written = try SettingsFile.replacingViewportPresets([], in: nil)
        XCTAssertEqual(String(decoding: written, as: UTF8.self), "{\n  \"viewportPresets\": []\n}\n")
    }

    func testABadFileIsAnErrorAndNothingIsWritten() {
        for bad in [
            "{ oops", "[]", #"{"viewportPresets": {}}"#,
            #"{"viewportPresets": [{"name": "A", "width": 0, "height": 5}]}"#,
        ] {
            XCTAssertThrowsError(try SettingsFile.viewportPresets(in: Data(bad.utf8)), bad)
        }
        XCTAssertThrowsError(try SettingsFile.replacingViewportPresets([], in: Data("{ oops".utf8))) { error in
            XCTAssertEqual(
                error.localizedDescription, "settings.json: line 1: Expected a key in quotes.")
        }
    }
}
