import Foundation

// On Apple platforms CGRect's geometry lives in CoreGraphics; on Linux, Foundation has it all.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// What a gesture needs to know about the canvas when it starts.
public struct GestureContext {
    public var screen: Screen
    public var tool: Tool
    public var selection: [RegionID]
    /// Whether snapping is on (`S`). Holding Option inverts it for the gesture.
    public var snappingEnabled: Bool
    public var gridSize: Int
    /// The canvas zoom, so distances meant in view points (the drag threshold, handle size) can be measured in
    /// screen points.
    public var zoom: Double

    public init(
        screen: Screen,
        tool: Tool,
        selection: [RegionID] = [],
        snappingEnabled: Bool = true,
        gridSize: Int = Snapping.defaultGridSize,
        zoom: Double = 1
    ) {
        self.screen = screen
        self.tool = tool
        self.selection = selection
        self.snappingEnabled = snappingEnabled
        self.gridSize = gridSize
        self.zoom = zoom
    }
}

/// One press, drag and release on the canvas, as spec Section 5 describes for each tool. The canvas feeds it pointer
/// positions in screen points and shows its `selection` and `preview`; on release it returns at most one command, so
/// a drag is one undo step. The screen isn't changed until that command is performed.
public struct CanvasGesture {
    /// How far, in view points, the pointer moves before a press counts as a drag.
    public static let dragThreshold = 3.0
    /// How close, in view points, the pointer must be to a handle's center to grab it. Handles are 7 pt squares.
    public static let handleRadius = 6.0

    public enum Preview: Equatable {
        case none
        /// Regions drawn at frames other than their own: moved regions with their descendants, or a resized region.
        case frames([RegionID: Frame])
        /// The region the Region tool is drawing.
        case newRegion(Frame)
        /// The marquee rectangle, in screen points.
        case marquee(CGRect)
    }

    /// What the details panel should do after a click (spec 6.1 and 6.4).
    public enum DetailsRequest: Equatable, Sendable {
        /// Open this region, committing any region open now.
        case open(RegionID)
        /// Commit and close the panel.
        case close
    }

    private enum Kind {
        case none
        case resize(region: RegionID, handle: ResizeHandle, original: Frame)
        /// `roots` are the topmost moved regions, the grabbed one first, so its origin is the one that snaps.
        case move(roots: [RegionID], originals: [RegionID: Frame])
        case draw
        case marquee(base: [RegionID])
        case writeClick
    }

    public let context: GestureContext
    public let start: CGPoint
    public private(set) var selection: [RegionID]
    public private(set) var preview: Preview = .none
    /// Whether the pointer has moved past the drag threshold. Until it does, a release is a click.
    public private(set) var isDragging = false
    /// The ID a region drawn by this gesture gets.
    public let newRegionID = RegionID.make()
    /// What the details panel should do, set on release. A region the gesture draws opens through its
    /// `CreateRegion` command instead.
    public private(set) var detailsRequest: DetailsRequest?

    private var kind: Kind = .none
    private var current: CGPoint
    /// The selection a release without a drag leaves, when it differs from the one the press made.
    private var clickSelection: [RegionID]?
    /// The press's click count: 2 for a double-click.
    private let clickCount: Int

    /// Starts a gesture with a press at `point`, in screen points. `clickCount` is 2 for the second press of a
    /// double-click.
    public init(
        pressAt point: CGPoint, modifiers: KeyCombo.Modifiers = [], clickCount: Int = 1, context: GestureContext
    ) {
        self.context = context
        self.clickCount = clickCount
        self.start = point
        self.current = point
        self.selection = context.selection
        let shift = modifiers.contains(.shift)

        switch context.tool {
        case .region:
            kind = .draw
        case .write:
            kind = .writeClick
        case .select:
            let index = RegionIndex(screen: context.screen)
            if selection.count == 1, let selected = index.region(selection[0]),
                let handle = ResizeHandle.handle(
                    at: point, on: selected.frame.cgRect, radius: Self.handleRadius / context.zoom)
            {
                kind = .resize(region: selected.id, handle: handle, original: selected.frame)
            } else if let hit = HitTesting.region(at: point, in: context.screen) {
                if shift {
                    selection = Selection.toggling(hit, in: selection)
                } else if selection.contains(hit) {
                    clickSelection = [hit]
                } else {
                    selection = [hit]
                }
                if selection.contains(hit) {
                    kind = Self.move(grabbing: hit, selection: selection, index: index)
                }
            } else {
                if !shift {
                    selection = []
                }
                kind = .marquee(base: selection)
            }
        }
    }

    private static func move(grabbing hit: RegionID, selection: [RegionID], index: RegionIndex) -> Kind {
        guard var roots = try? topmostRegions(selection, in: index).map(\.id) else { return .none }
        // The grabbed region, or the selected region it is inside, leads, so its origin snaps.
        if let grabbed = index.path(to: hit).first(where: { roots.contains($0.id) })?.id {
            roots.removeAll { $0 == grabbed }
            roots.insert(grabbed, at: 0)
        }
        var originals: [RegionID: Frame] = [:]
        for root in roots {
            for region in index.region(root)?.subtree ?? [] {
                originals[region.id] = region.frame
            }
        }
        return .move(roots: roots, originals: originals)
    }

    private func grid(optionHeld: Bool) -> Int? {
        Snapping.isActive(enabled: context.snappingEnabled, optionHeld: optionHeld) ? context.gridSize : nil
    }

    /// Follows the pointer to `point`, in screen points.
    public mutating func drag(to point: CGPoint, optionHeld: Bool = false) {
        current = point
        if !isDragging {
            let threshold = Self.dragThreshold / context.zoom
            guard abs(point.x - start.x) >= threshold || abs(point.y - start.y) >= threshold else { return }
            isDragging = true
        }
        let grid = grid(optionHeld: optionHeld)
        let dx = point.x - start.x
        let dy = point.y - start.y

        switch kind {
        case .none, .writeClick:
            break
        case .resize(let region, let handle, let original):
            let frame = Self.resizedFrame(original, handle: handle, dx: dx, dy: dy, grid: grid)
            preview = .frames([region: frame])
        case .move(let roots, let originals):
            let delta = moveDelta(roots: roots, originals: originals, dx: dx, dy: dy, grid: grid)
            preview = .frames(originals.mapValues { $0.offsetBy(dx: delta.x, dy: delta.y) })
        case .draw:
            preview = Self.drawnFrame(from: start, to: point, grid: grid).map(Preview.newRegion) ?? .none
        case .marquee(let base):
            let rect = CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
            selection = Selection.adding(HitTesting.regions(touching: rect, in: context.screen), to: base)
            preview = .marquee(rect)
        }
    }

    /// Recomputes the preview after Option is pressed or released mid-drag.
    public mutating func update(optionHeld: Bool) {
        guard isDragging else { return }
        drag(to: current, optionHeld: optionHeld)
    }

    /// Ends the gesture at `point` and returns the command to perform, if any. Afterwards `selection` is the
    /// selection to show, including a region the command draws.
    public mutating func release(at point: CGPoint, optionHeld: Bool = false) -> Command? {
        drag(to: point, optionHeld: optionHeld)
        defer { preview = .none }
        let screen = context.screen.id
        let grid = grid(optionHeld: optionHeld)

        guard isDragging else {
            if let clickSelection {
                selection = clickSelection
            }
            switch kind {
            case .writeClick:
                let hit = HitTesting.region(at: start, in: context.screen)
                selection = hit.map { [$0] } ?? []
                detailsRequest = hit.map(DetailsRequest.open) ?? .close
            case .move where clickCount >= 2:
                if let hit = HitTesting.region(at: start, in: context.screen) {
                    selection = [hit]
                    detailsRequest = .open(hit)
                }
            default:
                break
            }
            return nil
        }

        switch kind {
        case .none, .writeClick, .marquee:
            return nil
        case .resize(let region, let handle, let original):
            let frame = Self.resizedFrame(
                original, handle: handle, dx: point.x - start.x, dy: point.y - start.y, grid: grid)
            guard frame != original else { return nil }
            return ResizeRegion(screen: screen, region: region, frame: frame, edges: handle.edges)
        case .move(let roots, let originals):
            let dx = Int((point.x - start.x).rounded())
            let dy = Int((point.y - start.y).rounded())
            let delta = moveDelta(
                roots: roots, originals: originals, dx: point.x - start.x, dy: point.y - start.y, grid: grid)
            guard delta != (0, 0) else { return nil }
            return MoveRegions(screen: screen, regions: roots, dx: dx, dy: dy, grid: grid)
        case .draw:
            guard let frame = Self.drawnFrame(from: start, to: point, grid: grid) else { return nil }
            selection = [newRegionID]
            return CreateRegion(screen: screen, frame: frame, id: newRegionID)
        }
    }

    private func moveDelta(
        roots: [RegionID], originals: [RegionID: Frame], dx: Double, dy: Double, grid: Int?
    ) -> (x: Int, y: Int) {
        guard let first = roots.first.flatMap({ originals[$0] }) else { return (0, 0) }
        return MoveRegions.snappedDelta(
            moving: first, dx: Int(dx.rounded()), dy: Int(dy.rounded()), grid: grid)
    }

    // MARK: Frames

    /// The frame a Region-tool drag from `start` to `end` draws, or nil when the drag is under the minimum size before
    /// snapping, which makes it a click (spec Section 5). With a grid, every edge snaps; a side that snapping
    /// collapses spans grid steps in the direction of the drag until it meets the minimum.
    public static func drawnFrame(from start: CGPoint, to end: CGPoint, grid: Int?) -> Frame? {
        let rect = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y).standardized
        let minimum = Double(Geometry.minimumSize)
        guard rect.width >= minimum, rect.height >= minimum else { return nil }
        let rounded = Frame(rounding: rect.minX, y: rect.minY, w: rect.width, h: rect.height)
        guard let grid, grid > 1 else { return rounded }

        func snapSpan(_ lower: Int, _ upper: Int, forward: Bool) -> (Int, Int) {
            var lower = Snapping.snap(lower, grid: grid)
            var upper = Snapping.snap(upper, grid: grid)
            while upper - lower < Geometry.minimumSize {
                if forward { upper += grid } else { lower -= grid }
            }
            return (lower, upper)
        }
        let (minX, maxX) = snapSpan(rounded.x, rounded.maxX, forward: end.x >= start.x)
        let (minY, maxY) = snapSpan(rounded.y, rounded.maxY, forward: end.y >= start.y)
        return Frame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    /// `original` with `handle` dragged by `dx`, `dy` screen points. The opposite edges stay put, and a dragged edge
    /// stops where the frame would go below the minimum size. With a grid, the dragged edges snap; if that would go
    /// below the minimum, the edge moves to the next grid line outward.
    public static func resizedFrame(
        _ original: Frame, handle: ResizeHandle, dx: Double, dy: Double, grid: Int?
    ) -> Frame {
        let edges = handle.edges
        let minimum = Geometry.minimumSize

        func span(lower: Int, upper: Int, delta: Double, movesLower: Bool, movesUpper: Bool) -> (Int, Int) {
            var lower = lower
            var upper = upper
            if movesLower {
                lower = min(Int((Double(lower) + delta).rounded()), upper - minimum)
                if let grid, grid > 1 {
                    lower = Snapping.snap(lower, grid: grid)
                    while upper - lower < minimum { lower -= grid }
                }
            } else if movesUpper {
                upper = max(Int((Double(upper) + delta).rounded()), lower + minimum)
                if let grid, grid > 1 {
                    upper = Snapping.snap(upper, grid: grid)
                    while upper - lower < minimum { upper += grid }
                }
            }
            return (lower, upper)
        }

        let (minX, maxX) = span(
            lower: original.x, upper: original.maxX, delta: dx,
            movesLower: edges.contains(.left), movesUpper: edges.contains(.right))
        let (minY, maxY) = span(
            lower: original.y, upper: original.maxY, delta: dy,
            movesLower: edges.contains(.top), movesUpper: edges.contains(.bottom))
        return Frame(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}
