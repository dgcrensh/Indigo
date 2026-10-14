import Foundation

@testable import DescriberCore

/// A random number generator that gives the same numbers for the same seed (SplitMix64), so a failing case can be
/// replayed from the seed it prints.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < probability
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}

/// Random screens for checking edits against `ReferenceCommands`: 50 to 300 regions nested up to five deep, with
/// overlapping and equal-size siblings, a few regions outside their parent's content, and scrolling regions with
/// saved offsets, some past the end of their content. The same seed always gives the same screen and IDs.
struct RandomScreen {
    /// Where top-level regions go by default: the canvas and a little below it.
    static let canvasDesk = Frame(x: 0, y: 0, w: 1440, h: 1200)
    /// A desk reaching far outside the canvas on every side, into negative coordinates, so regions span many cells of
    /// the placement grid and scrolling content can be larger than the grid puts in cells.
    static let wideDesk = Frame(x: -4000, y: -3000, w: 10000, h: 8000)

    let project: Project
    let screen: Screen
    let offsets: [RegionID: ScrollOffset]

    init(seed: UInt64, desk: Frame = canvasDesk) {
        var random = SeededGenerator(seed: seed)
        let screen = Screen(
            id: ScreenID("00000000-0000-4000-8000-000000000777"), name: "Random",
            viewport: Viewport(width: 1440, height: 900))
        let count = random.int(50...300)
        var placed: [(region: Region, depth: Int)] = []
        var offsets: [RegionID: ScrollOffset] = [:]

        for number in 1...count {
            let candidates = placed.filter { $0.depth < 5 && $0.region.contentArea.w >= 8 }
            let parent = random.chance(0.2) ? nil : candidates.randomElement(using: &random)
            let area = parent?.region.contentArea ?? desk
            var frame: Frame
            if let sibling = (parent?.region.children ?? screen.regions).randomElement(using: &random),
                random.chance(0.1)
            {
                frame = sibling.frame
            } else if random.chance(0.05) {
                frame = Self.frame(in: desk, using: &random)
            } else {
                frame = Self.frame(in: area, using: &random)
            }
            frame.w = max(frame.w, 4)
            frame.h = max(frame.h, 4)
            var scroll: Scroll?
            if frame.w >= 40, frame.h >= 40, random.chance(0.15) {
                let axis = [ScrollAxis.vertical, .horizontal, .both].randomElement(using: &random)!
                scroll = Scroll(
                    axis: axis, contentWidth: frame.w * random.int(1...3), contentHeight: frame.h * random.int(1...3))
            }
            let region = Region(
                id: RegionID(String(format: "00000000-0000-4000-8000-%012d", number)), title: "Region \(number)",
                frame: frame, scroll: scroll)
            if scroll != nil, random.chance(0.7) {
                offsets[region.id] = ScrollOffset(x: random.int(-20...frame.w * 2), y: random.int(-20...frame.h * 2))
            }
            if let parent {
                parent.region.children.append(region)
            } else {
                screen.regions.append(region)
            }
            placed.append((region, (parent?.depth ?? 0) + 1))
        }
        self.project = Project(name: "Random \(seed)", screens: [screen])
        self.screen = screen
        self.offsets = offsets
    }

    /// A frame at least 4 × 4 that mostly fits `area`.
    static func frame(in area: Frame, using random: inout SeededGenerator) -> Frame {
        let w = random.int(4...max(4, area.w * 2 / 3))
        let h = random.int(4...max(4, area.h * 2 / 3))
        let x = area.x + random.int(0...max(0, area.w - w))
        let y = area.y + random.int(0...max(0, area.h - h))
        return Frame(x: x, y: y, w: w, h: h)
    }

    /// Every region on `screen` in draw order, with its parent, frame and scrolling: equal lines mean equal trees.
    static func tree(of screen: Screen) -> [String] {
        var lines: [String] = []
        func add(_ regions: [Region], parent: RegionID?) {
            for region in regions {
                let frame = region.frame
                lines.append(
                    "\(region.id) in \(parent?.rawValue ?? "top") at \(frame.x),\(frame.y) \(frame.w)×\(frame.h)"
                        + (region.scroll.map { " scrolls \($0.contentWidth)×\($0.contentHeight)" } ?? ""))
                add(region.children, parent: region.id)
            }
        }
        add(screen.regions, parent: nil)
        return lines
    }
}
