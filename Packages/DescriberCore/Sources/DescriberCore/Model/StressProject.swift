import Foundation

extension Project {
    /// A project for performance checks: `screenCount` 1440 × 900 pt screens each holding exactly `regionCount`
    /// regions, laid out the same way every time. Containers sit in a four-column grid that runs past the bottom of
    /// the frame, each holding rows that hold small items, so a screen has nesting, long titles to truncate, and
    /// regions outside the frame. Every region is already under the parent the parenting rule picks. With more than
    /// one screen, each container links to the next screen, so screen names appear in other screens' files.
    public static func stressTest(regionCount: Int, screenCount: Int = 1) -> Project {
        let screens = (0..<screenCount).map { index in
            Screen(
                id: ScreenID(String(format: "00000000-0000-4000-8000-%012d", 500 + index)),
                name: screenCount == 1 ? "Stress" : "Stress \(index + 1)",
                viewport: Viewport(width: 1440, height: 900)
            )
        }
        for (index, screen) in screens.enumerated() {
            let next = screenCount == 1 ? nil : screens[(index + 1) % screenCount].id
            fill(screen, number: index, regionCount: regionCount, linkingTo: next)
        }
        return Project(name: "Stress Test", screens: screens)
    }

    private static func fill(_ screen: Screen, number: Int, regionCount: Int, linkingTo next: ScreenID?) {
        var made = 0
        func region(_ title: String, _ frame: Frame) -> Region? {
            guard made < regionCount else { return nil }
            made += 1
            return Region(
                id: RegionID(String(format: "00000000-%04d-4000-8000-%012d", number, made)),
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
            if let next {
                box.links = [Link(screen: next, trigger: "click")]
            }
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
    }
}
