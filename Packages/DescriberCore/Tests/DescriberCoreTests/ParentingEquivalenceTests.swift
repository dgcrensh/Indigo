import XCTest

@testable import DescriberCore

/// The commands that re-place regions leave exactly the trees `ReferenceCommands` (the commands as `main` ran them
/// before milestone 17) leaves, region for region, on hundreds of random screens. A failure names its seed.
final class ParentingEquivalenceTests: XCTestCase {
    private let seeds: Range<UInt64> = 0..<200

    /// Applies `command` to one copy of the screen for `seed` and `reference` to another, and compares the trees.
    private func assertSameTrees(
        seed: UInt64,
        _ make: (RandomScreen, inout SeededGenerator) -> (command: Command, reference: (Project) throws -> Void)?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let subject = RandomScreen(seed: seed)
        let reference = RandomScreen(seed: seed)
        var random = SeededGenerator(seed: seed &+ 1_000_000)
        guard let (command, applyReference) = make(subject, &random) else { return }
        let result = Result { _ = try command.apply(to: subject.project) }
        let referenceResult = Result { try applyReference(reference.project) }
        switch (result, referenceResult) {
        case (.success, .success):
            XCTAssertEqual(
                RandomScreen.tree(of: subject.screen), RandomScreen.tree(of: reference.screen),
                "\(command.actionName), seed \(seed)", file: file, line: line)
        case (.failure(let error), .failure(let referenceError)):
            XCTAssertEqual(
                "\(error)", "\(referenceError)", "\(command.actionName), seed \(seed)", file: file, line: line)
        default:
            XCTFail(
                "\(command.actionName), seed \(seed): \(result) but the reference gave \(referenceResult)",
                file: file, line: line)
        }
    }

    func testMovingASelectionMatchesTheReference() {
        for seed in seeds {
            assertSameTrees(seed: seed) { subject, random in
                let all = subject.screen.allRegions
                var selection = (0..<random.int(1...20)).map { _ in all.randomElement(using: &random)!.id }
                if random.chance(0.3), let parent = all.first(where: { !$0.children.isEmpty }) {
                    // A parent and its child together: the child moves once, with its parent.
                    selection += [parent.id, parent.children.randomElement(using: &random)!.id]
                }
                let layout = ScrollLayout(screen: subject.screen, offsets: subject.offsets)
                if random.chance(0.5), let hidden = all.first(where: { layout.visibleFrame(of: $0.id) == nil }) {
                    selection.append(hidden.id)
                }
                selection.shuffle(using: &random)
                let command = MoveRegions(
                    screen: subject.screen.id, regions: selection, dx: random.int(-300...300),
                    dy: random.int(-300...300), grid: random.chance(0.25) ? 8 : nil, scrollOffsets: subject.offsets)
                return (command, { try ReferenceCommands.apply(command, to: $0) })
            }
        }
    }

    func testResizingSoChildrenFallOutMatchesTheReference() {
        for seed in seeds {
            assertSameTrees(seed: seed) { subject, random in
                let all = subject.screen.allRegions
                let parents = all.filter { !$0.children.isEmpty }
                let target = (random.chance(0.8) ? parents.randomElement(using: &random) : nil) ?? all[0]
                let layout = ScrollLayout(screen: subject.screen, offsets: subject.offsets)
                let drawn = layout.drawnFrame(of: target.id)!
                let frame = Frame(
                    x: drawn.x + random.int(-20...drawn.w / 2), y: drawn.y + random.int(-20...drawn.h / 2),
                    w: random.int(4...max(4, drawn.w)), h: random.int(4...max(4, drawn.h)))
                let command = ResizeRegion(
                    screen: subject.screen.id, region: target.id, frame: frame, grid: random.chance(0.25) ? 8 : nil,
                    scrollOffsets: subject.offsets)
                return (command, { try ReferenceCommands.apply(command, to: $0) })
            }
        }
    }

    func testPastingSeveralRegionsMatchesTheReference() {
        for seed in seeds {
            assertSameTrees(seed: seed) { subject, random in
                let all = subject.screen.allRegions
                let copied = (0..<random.int(1...6)).map { _ in all.randomElement(using: &random)! }
                let parent = random.chance(0.3) ? all.randomElement(using: &random)!.id : nil
                let command = PasteRegions(
                    screen: subject.screen.id, regions: copied, parent: parent, scrollOffsets: subject.offsets)
                // The same copies, with the same new IDs, so the trees can be compared.
                let pasted = command.pasted.map { $0.copy() }
                return (command, { try ReferenceCommands.apply(command, pasting: pasted, to: $0) })
            }
        }
    }

    func testTurningScrollingOffOrShrinkingItMatchesTheReference() {
        var checked = 0
        for seed in seeds {
            assertSameTrees(seed: seed) { subject, random in
                let scrolling = subject.screen.allRegions.filter { $0.scroll != nil && !$0.children.isEmpty }
                guard let target = scrolling.randomElement(using: &random), let scroll = target.scroll else {
                    return nil
                }
                checked += 1
                let shrunk = Scroll(
                    axis: scroll.axis, contentWidth: max(target.frame.w, scroll.contentWidth / 2),
                    contentHeight: max(target.frame.h, scroll.contentHeight / 2))
                let command = SetRegionScroll(
                    region: target.id, scroll: random.chance(0.5) ? nil : shrunk, scrollOffsets: subject.offsets)
                return (command, { try ReferenceCommands.apply(command, to: $0) })
            }
        }
        XCTAssertGreaterThan(checked, 100)
    }
}
