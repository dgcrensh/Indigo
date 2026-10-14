import XCTest

@testable import DescriberCore

final class ToolTests: XCTestCase {
    func testToastTexts() {
        XCTAssertEqual(Toast.tool(.select).text(), "Select tool — V")
        XCTAssertEqual(Toast.tool(.region).text(), "Region tool — R")
        XCTAssertEqual(Toast.tool(.write).text(), "Write tool — W")
        XCTAssertEqual(Toast.snapping(on: true).text(), "Snapping on — S")
        XCTAssertEqual(Toast.snapping(on: false).text(), "Snapping off — S")
        XCTAssertEqual(Toast.gridSize(16).text(), "Grid 16 pt")
    }

    func testToastsUseTheRegistrysKey() {
        let registry = KeybindRegistry(overrides: [.regionTool: [KeyCombo("b", .shift)]])
        XCTAssertEqual(Toast.tool(.region).text(keybinds: registry), "Region tool — ⇧B")
        let none = KeybindRegistry(overrides: [.writeTool: []])
        XCTAssertEqual(Toast.tool(.write).text(keybinds: none), "Write tool")
    }

    func testSelectionHelpers() {
        let a = RegionID("a")
        let b = RegionID("b")
        let c = RegionID("c")
        XCTAssertEqual(Selection.toggling(b, in: [a]), [a, b])
        XCTAssertEqual(Selection.toggling(a, in: [a, b]), [b])
        XCTAssertEqual(Selection.adding([b, c, a], to: [a, b]), [a, b, c])

        let (_, screen, outer, inner, _) = Fixtures.nestedProject()
        XCTAssertEqual(Selection.pruned([inner.id, a, outer.id], to: screen), [inner.id, outer.id])
    }
}
