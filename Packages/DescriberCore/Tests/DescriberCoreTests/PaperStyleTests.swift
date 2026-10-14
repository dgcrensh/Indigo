import XCTest

@testable import DescriberCore

/// The Paper look's palette, kind families and corner radii (milestone 13).
final class PaperPaletteTests: XCTestCase {
    func testEveryKindBelongsToItsFamily() {
        let expected: [RegionKind: KindFamily] = [
            .open: .neutral,
            .container: .structure, .list: .structure, .navigation: .structure,
            .text: .content, .image: .content,
            .button: .action, .menuItem: .action,
            .input: .input, .toggle: .input, .picker: .input,
        ]
        XCTAssertEqual(Set(expected.keys), Set(RegionKind.allCases))
        for kind in RegionKind.allCases {
            XCTAssertEqual(kind.family, expected[kind], "\(kind)")
        }
        XCTAssertEqual(RegionKind.allCases.filter(\.isUnfilled), [.text])
        for appearance in PaperAppearance.allCases {
            let palette = PaperPalette.palette(for: appearance)
            XCTAssertEqual(Set(palette.families.keys), Set(KindFamily.allCases), "\(appearance)")
        }
    }

    func testTheTableColorsAreUsed() {
        XCTAssertEqual(PaperPalette.light.colors(for: .button).fill, PaperColor(hex: 0xFBE1CC))
        XCTAssertEqual(PaperPalette.light.accent, PaperColor(hex: 0x4A4FD1))
        XCTAssertEqual(PaperPalette.dark.accent, PaperColor(hex: 0x8C90F0))
        XCTAssertEqual(PaperPalette.dark.colors(for: .toggle).text, PaperColor(hex: 0xCDEEDF))
        let accent = PaperColor(hex: 0x4A4FD1)
        XCTAssertEqual(accent.red * 255, 0x4A, accuracy: 0.001)
        XCTAssertEqual(accent.green * 255, 0x4F, accuracy: 0.001)
        XCTAssertEqual(accent.blue * 255, 0xD1, accuracy: 0.001)
    }

    func testContrastFollowsWCAG() {
        let black = PaperColor(hex: 0x000000)
        let white = PaperColor(hex: 0xFFFFFF)
        XCTAssertEqual(Contrast.ratio(black, white), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(white, white), 1, accuracy: 0.0001)
        XCTAssertEqual(Contrast.ratio(PaperColor(hex: 0x777777), white), 4.48, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(black.withAlpha(0), white), 1, accuracy: 0.0001, "clear shows the background")
    }

    func testTextPassesOnTheSurfacesItSitsOn() {
        for appearance in PaperAppearance.allCases {
            let palette = PaperPalette.palette(for: appearance)
            for family in KindFamily.allCases {
                let colors = palette.colors(for: family)
                assertContrast(colors.text, on: colors.fill, atLeast: 4.5, "\(appearance) \(family) title")
            }
            for surface in [palette.sheet, palette.card, palette.chrome, palette.well] {
                assertContrast(palette.ink, on: surface, atLeast: 4.5, "\(appearance) ink")
            }
            for surface in [palette.chrome, palette.card] {
                assertContrast(palette.secondaryInk, on: surface, atLeast: 4.5, "\(appearance) secondary ink")
            }
            for surface in [palette.sheet, palette.card] {
                assertContrast(palette.accent, on: surface, atLeast: 3, "\(appearance) accent")
            }
            assertContrast(palette.onAccent, on: palette.accent, atLeast: 4.5, "\(appearance) on-accent")
            let text = palette.colors(for: .text)
            assertContrast(text.border, on: palette.sheet, atLeast: 1.5, "\(appearance) unfilled text region")
        }
    }

    private func assertContrast(
        _ foreground: PaperColor, on background: PaperColor, atLeast minimum: Double, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ratio = Contrast.ratio(foreground, background)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(message): \(ratio)", file: file, line: line)
    }
}

final class PaperShapesTests: XCTestCase {
    func testRegionCornersAreCappedForSmallRegions() {
        XCTAssertEqual(PaperShapes.regionCornerRadius(width: 200, height: 80), 6)
        XCTAssertEqual(PaperShapes.regionCornerRadius(width: 4, height: 20), 1)
        XCTAssertEqual(PaperShapes.regionCornerRadius(width: 20, height: 16), 4)
        XCTAssertEqual(PaperShapes.regionCornerRadius(width: 0, height: 0), 0)
    }

    func testSheetCornersFollowTheDevice() {
        func screen(_ preset: String?, kind: ScreenKind = .screen) -> Screen {
            Screen(name: "S", kind: kind, viewport: Viewport(preset: preset, width: 400, height: 800))
        }
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("iphone-15")), 55)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("iphone-se")), 55)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("iphone-15-pro-max")), 55)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("ipad")), 18)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("ipad-pro-13")), 18)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("iphone-15", kind: .menu)), 12)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen(nil, kind: .alert)), 12)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("laptop")), 0)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("desktop")), 0)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen(ViewportPresets.thisDeviceID)), 0)
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen(nil)), 0, "Custom")
        XCTAssertEqual(PaperShapes.sheetCornerRadius(for: screen("my-monitor")), 0, "a user or unknown preset")
    }
}

final class ToolPillTooltipTests: XCTestCase {
    func testTooltipsNameTheCurrentKeys() {
        XCTAssertEqual(ToolPillTooltip.text(for: .region), "Region tool (R)")
        let registry = KeybindRegistry(overrides: [.regionTool: [KeyCombo("b", .shift)], .writeTool: []])
        XCTAssertEqual(ToolPillTooltip.text(for: .region, keybinds: registry), "Region tool (⇧B)")
        XCTAssertEqual(ToolPillTooltip.text(for: .write, keybinds: registry), "Write tool")
        XCTAssertEqual(ToolPillTooltip.snapping(), "Snapping (S). Option-click for grid size (G)")
    }
}
