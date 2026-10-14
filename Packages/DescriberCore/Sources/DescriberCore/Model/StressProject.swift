import Foundation

extension Project {
    /// A project for performance checks: one 1440 × 900 pt screen holding exactly `regionCount` regions, laid out
    /// the same way every time. Containers sit in a four-column grid that runs past the bottom of the frame, each
    /// holding rows that hold small items, so the screen has nesting, long titles to truncate, and regions outside
    /// the frame. Every region is already under the parent the parenting rule picks.
    public static func stressTest(regionCount: Int) -> Project {
        let screen = Screen(
            id: ScreenID("00000000-0000-4000-8000-000000000500"),
            name: "Stress",
            viewport: Viewport(width: 1440, height: 900)
        )
        var made = 0
        func region(_ title: String, _ frame: Frame) -> Region? {
            guard made < regionCount else { return nil }
            made += 1
            return Region(
                id: RegionID(String(format: "00000000-0000-4000-8000-%012d", made)),
                title: title,
                frame: frame
            )
        }

        var container = 0
        while made < regionCount {
            let x = 16 + (container % 4) * 356
            let y = 16 + (container / 4) * 316
            container += 1
            guard let box = region("Container \(container)", Frame(x: x, y: y, w: 340, h: 300)) else { break }
            screen.regions.append(box)
            for row in 1...5 {
                let rowFrame = Frame(x: x + 16, y: y + 16 + (row - 1) * 56, w: 308, h: 48)
                guard let rowRegion = region("Row \(container).\(row)", rowFrame) else { break }
                box.children.append(rowRegion)
                for item in 1...3 {
                    let itemFrame = Frame(x: rowFrame.x + 8 + (item - 1) * 100, y: rowFrame.y + 8, w: 92, h: 32)
                    guard let itemRegion = region("Item \(container).\(row).\(item) with a long title", itemFrame)
                    else { break }
                    rowRegion.children.append(itemRegion)
                }
            }
        }
        return Project(name: "Stress Test", screens: [screen])
    }
}
