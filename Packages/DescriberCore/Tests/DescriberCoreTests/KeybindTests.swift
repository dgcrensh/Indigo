import XCTest

@testable import DescriberCore

final class KeybindTests: XCTestCase {
    private let registry = KeybindRegistry.defaults

    func testEveryActionHasADefault() {
        for action in KeyAction.allCases {
            XCTAssertFalse(registry.combos(for: action).isEmpty, "\(action) has no default")
        }
    }

    func testNoDefaultCombinationIsUsedTwice() {
        let combos = KeyAction.allCases.flatMap { registry.combos(for: $0) }
        XCTAssertEqual(Set(combos).count, combos.count)
    }

    func testSpecDefaultsResolve() {
        let expected: [(String, KeyAction)] = [
            ("v", .selectTool),
            ("r", .regionTool),
            ("w", .writeTool),
            ("s", .toggleSnapping),
            ("g", .gridSize),
            ("shift-d", .toggleAllDescriptions),
            ("shift-return", .selectParent),
            ("return", .selectChildren),
            ("cmd-option-left", .back),
            ("cmd-option-down", .nextScreen),
            ("cmd-]", .bringToFront),
            ("cmd-=", .zoomIn),
            ("cmd--", .zoomOut),
            ("ctrl-cmd-s", .toggleSidebar),
            ("forward-delete", .delete),
            ("shift-cmd-z", .redo),
        ]
        for (string, action) in expected {
            let combo = KeyCombo(parsing: string)
            XCTAssertNotNil(combo, string)
            XCTAssertEqual(combo.flatMap { registry.action(for: $0) }, action, string)
        }
    }

    func testParsingAndDescribingRoundTrip() throws {
        for action in KeyAction.allCases {
            for combo in registry.combos(for: action) {
                XCTAssertEqual(KeyCombo(parsing: combo.description), combo, combo.description)
            }
        }
        XCTAssertEqual(KeyCombo(parsing: "Command-Alt-Left"), KeyCombo("left", [.command, .option]))
        XCTAssertEqual(KeyCombo(parsing: "SHIFT-D"), KeyCombo("d", .shift))
        XCTAssertEqual(KeyCombo(parsing: "-"), KeyCombo("-"))
        XCTAssertEqual(KeyCombo(parsing: "control-cmd-s"), KeyCombo("s", [.control, .command]))
    }

    func testBadStringsDoNotParse() {
        for string in ["", "shift-", "hyper-d", "cmd-left-arrow", "ab", "cmd-"] {
            XCTAssertNil(KeyCombo(parsing: string), string)
        }
    }

    func testDisplayStrings() {
        XCTAssertEqual(KeyCombo("r").displayString, "R")
        XCTAssertEqual(KeyCombo("d", .shift).displayString, "⇧D")
        XCTAssertEqual(KeyCombo("left", [.command, .option]).displayString, "⌥⌘←")
        XCTAssertEqual(KeyCombo("return", .shift).displayString, "⇧↩")
    }

    func testAnOverrideMovesACombinationOffItsDefaultAction() {
        let registry = KeybindRegistry(overrides: [.regionTool: [KeyCombo("b")], .writeTool: [KeyCombo("v")]])
        XCTAssertEqual(registry.action(for: KeyCombo("b")), .regionTool)
        XCTAssertNil(registry.action(for: KeyCombo("r")))
        XCTAssertEqual(registry.action(for: KeyCombo("v")), .writeTool)
        XCTAssertEqual(registry.combos(for: .selectTool), [])
        XCTAssertEqual(registry.combos(for: .writeTool), [KeyCombo("v")])
    }

    func testOnlyStandardEditingShortcutsResolveWhileEditingText() {
        XCTAssertNil(registry.action(for: KeyCombo("v"), isEditingText: true))
        XCTAssertNil(registry.action(for: KeyCombo("return"), isEditingText: true))
        XCTAssertNil(registry.action(for: KeyCombo("left"), isEditingText: true))
        XCTAssertNil(registry.action(for: KeyCombo("d", .command), isEditingText: true))
        XCTAssertEqual(registry.action(for: KeyCombo("z", .command), isEditingText: true), .undo)
        XCTAssertEqual(registry.action(for: KeyCombo("v", .command), isEditingText: true), .paste)
        XCTAssertEqual(registry.action(for: KeyCombo("v"), isEditingText: false), .selectTool)
    }
}
