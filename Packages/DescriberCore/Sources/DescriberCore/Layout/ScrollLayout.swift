import Foundation

// On Apple platforms CGRect's geometry lives in CoreGraphics; on Linux, Foundation has it all.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How far each scrolling region on a screen is scrolled, and where that draws every region (spec Section 5).
///
/// Frames in the file are as if nothing were scrolled (spec 3.4). The canvas draws a region inside scrolling content
/// moved up and left by the offsets of the scrolling regions around it, and clips it to their frames. Those are its
/// *drawn* frame and its clip, in screen points; gestures work in drawn frames. With no offsets, a region's drawn
/// frame is its own frame, but children are still clipped to a scrolling parent's frame.
///
/// Built from the screen as it is now, like `RegionIndex`, so build a new one after each command or scroll.
public struct ScrollLayout {
    private struct Entry {
        let drawn: Frame
        /// The intersection of the drawn frames of the scrolling regions around this one, or nil when there are none.
        let clip: Frame?
        /// What this region's children's frames are moved by: its own shift plus its offset.
        let contentShift: ScrollOffset
    }

    public private(set) var index: RegionIndex
    /// In the same positions as `index.regions`.
    private var entries: [Entry] = []
    /// The offsets the layout was built with, before clamping.
    private let saved: [RegionID: ScrollOffset]
    /// The offset of every region scrolled away from its origin, clamped.
    public private(set) var offsets: [RegionID: ScrollOffset] = [:]

    /// `offsets` are the saved offsets of the screen's editor state; offsets of regions that no longer scroll, or
    /// past the end of their content, are clamped.
    public init(screen: Screen, offsets: [RegionID: ScrollOffset] = [:]) {
        index = RegionIndex(screen: screen)
        saved = offsets
        entries.reserveCapacity(index.regions.count)
        add(screen.regions, shift: .zero, clip: nil)
    }

    /// Adds `region` and its subtree as the last top-level region, as appending it to the screen's regions and
    /// building a new layout would. A top-level region has no shift or clip, so nothing else moves.
    mutating func appendTopLevel(_ region: Region) {
        index.appendTopLevel(region)
        add([region], shift: .zero, clip: nil)
    }

    /// Walks in draw order, so each entry lands at its region's position in `index`.
    private mutating func add(_ regions: [Region], shift: ScrollOffset, clip: Frame?) {
        for region in regions {
            let drawn = region.frame.offsetBy(dx: -shift.x, dy: -shift.y)
            var contentShift = shift
            var childClip = clip
            if region.scroll != nil {
                let offset = Self.clamped(saved[region.id] ?? .zero, in: region)
                if offset != .zero {
                    offsets[region.id] = offset
                }
                contentShift = ScrollOffset(x: shift.x + offset.x, y: shift.y + offset.y)
                childClip = clip.map { $0.intersection(drawn) ?? Frame(x: drawn.x, y: drawn.y, w: 0, h: 0) } ?? drawn
            }
            entries.append(Entry(drawn: drawn, clip: clip, contentShift: contentShift))
            add(region.children, shift: contentShift, clip: childClip)
        }
    }

    private func entry(_ id: RegionID) -> Entry? {
        index.position(of: id).map { entries[$0] }
    }

    // MARK: Offsets

    /// The furthest `region` scrolls: content minus frame along each axis it scrolls, zero along the others.
    public static func maximumOffset(of region: Region) -> ScrollOffset {
        guard let scroll = region.scroll else { return .zero }
        let x = scroll.axis == .vertical ? 0 : max(scroll.contentWidth - region.frame.w, 0)
        let y = scroll.axis == .horizontal ? 0 : max(scroll.contentHeight - region.frame.h, 0)
        return ScrollOffset(x: x, y: y)
    }

    /// `offset` kept between zero and `region`'s maximum on each axis.
    public static func clamped(_ offset: ScrollOffset, in region: Region) -> ScrollOffset {
        let maximum = maximumOffset(of: region)
        return ScrollOffset(x: min(max(offset.x, 0), maximum.x), y: min(max(offset.y, 0), maximum.y))
    }

    /// How far `id` is scrolled: zero unless it scrolls.
    public func offset(of id: RegionID) -> ScrollOffset {
        offsets[id] ?? .zero
    }

    /// Whether `id` has content to scroll along some axis.
    public func canScroll(_ id: RegionID) -> Bool {
        guard let region = index.region(id) else { return false }
        return Self.maximumOffset(of: region) != .zero
    }

    /// The offset `id` has after scrolling its content by `dx`, `dy` screen points, clamped; positive moves the
    /// content left and up. Nil when `id` doesn't scroll.
    public func scrolled(_ id: RegionID, byDX dx: Int, dy: Int) -> ScrollOffset? {
        guard let region = index.region(id), region.scroll != nil else { return nil }
        let current = offset(of: id)
        return Self.clamped(ScrollOffset(x: current.x + dx, y: current.y + dy), in: region)
    }

    // MARK: Where regions are drawn

    /// Where the canvas draws `id`, in screen points.
    public func drawnFrame(of id: RegionID) -> Frame? {
        entry(id)?.drawn
    }

    /// Where the canvas draws the region at draw order `position`.
    func drawnFrame(at position: Int) -> Frame {
        entries[position].drawn
    }

    /// The rectangle `id` is clipped to, or nil when no scrolling region is around it. A clip with no area hides it.
    public func clip(of id: RegionID) -> Frame? {
        entry(id)?.clip
    }

    /// The part of `id` that shows: its drawn frame inside its clip. Nil when it is entirely clipped away.
    public func visibleFrame(of id: RegionID) -> Frame? {
        index.position(of: id).flatMap(visibleFrame(at:))
    }

    /// The part of the region at draw order `position` that shows.
    func visibleFrame(at position: Int) -> Frame? {
        let entry = entries[position]
        guard let clip = entry.clip else { return entry.drawn }
        return entry.drawn.intersection(clip)
    }

    /// What the frames of `parent`'s children are moved by where they are drawn; zero for the top level.
    public func contentShift(of parent: RegionID?) -> ScrollOffset {
        parent.flatMap { entry($0)?.contentShift } ?? .zero
    }

    /// `id`'s content area where it is drawn at its scroll position: the frame for a region that doesn't scroll.
    public func drawnContentArea(of id: RegionID) -> Frame? {
        index.position(of: id).map(drawnContentArea(at:))
    }

    /// The content area of the region at draw order `position` where it is drawn.
    func drawnContentArea(at position: Int) -> Frame {
        let shift = entries[position].contentShift
        return index.regions[position].contentArea.offsetBy(dx: -shift.x, dy: -shift.y)
    }

    /// The frame in the file of a region drawn at `drawn` as a child of `parent` (nil for the top level).
    public func fileFrame(forDrawn drawn: Frame, inParent parent: RegionID?) -> Frame {
        let shift = contentShift(of: parent)
        return drawn.offsetBy(dx: shift.x, dy: shift.y)
    }

    /// The frame `id` is drawn at and the clip it is drawn with while a gesture previews `frames` (drawn frames).
    /// A previewed region is clipped only by previewed scrolling regions around it, so a region dragged out of
    /// scrolling content stays in view; any other region is drawn as usual.
    public func drawn(_ id: RegionID, previewing frames: [RegionID: Frame]) -> (frame: Frame, clip: Frame?)? {
        guard let entry = entry(id) else { return nil }
        guard let frame = frames[id] else { return (entry.drawn, entry.clip) }
        var clip: Frame?
        for ancestor in index.path(to: id).dropLast() where ancestor.scroll != nil {
            guard let ancestorFrame = frames[ancestor.id] else { continue }
            clip =
                clip.map { $0.intersection(ancestorFrame) ?? Frame(x: frame.x, y: frame.y, w: 0, h: 0) }
                ?? ancestorFrame
        }
        return (frame, clip)
    }

    // MARK: Hit testing

    /// The topmost region whose visible part contains `point`, edges included.
    public func region(at point: CGPoint) -> RegionID? {
        index.regions.indices.last { position in
            visibleFrame(at: position)?.cgRect.containsIncludingEdges(point) ?? false
        }.map { index.regions[$0].id }
    }

    /// Every region whose visible part `rect` overlaps, in draw order. A rectangle with no area touches nothing.
    public func regions(touching rect: CGRect) -> [RegionID] {
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0 else { return [] }
        return index.regions.indices.filter { position in
            visibleFrame(at: position)?.cgRect.intersects(rect) ?? false
        }.map { index.regions[$0].id }
    }

    /// The region two-finger scroll over `point` scrolls (spec Section 5): the topmost of `selection` that has
    /// content to scroll and whose visible part contains the point. Nil means the canvas pans.
    public func scrollTarget(at point: CGPoint, among selection: [RegionID]) -> RegionID? {
        let selected = Set(selection)
        return index.regions.indices.last { position in
            let region = index.regions[position]
            return selected.contains(region.id) && Self.maximumOffset(of: region) != .zero
                && visibleFrame(at: position)?.cgRect.containsIncludingEdges(point) == true
        }.map { index.regions[$0].id }
    }

    // MARK: Indicators

    /// Where a scrolling region's frame sits in its content along one axis, as fractions of the frame's length.
    public struct Indicator: Equatable, Sendable {
        public enum Axis: Sendable {
            /// A bar along the right edge.
            case vertical
            /// A bar along the bottom edge.
            case horizontal
        }

        public var axis: Axis
        /// Where the bar starts, from 0 (the content's start shows) toward 1.
        public var start: Double
        /// The bar's length: the frame's share of the content.
        public var length: Double
    }

    /// One indicator for each axis along which `id` has content to scroll.
    public func indicators(of id: RegionID) -> [Indicator] {
        guard let region = index.region(id), let scroll = region.scroll else { return [] }
        let maximum = Self.maximumOffset(of: region)
        let offset = offset(of: id)
        var indicators: [Indicator] = []
        if maximum.y > 0 {
            let content = Double(scroll.contentHeight)
            indicators.append(
                Indicator(
                    axis: .vertical, start: Double(offset.y) / content, length: Double(region.frame.h) / content))
        }
        if maximum.x > 0 {
            let content = Double(scroll.contentWidth)
            indicators.append(
                Indicator(
                    axis: .horizontal, start: Double(offset.x) / content, length: Double(region.frame.w) / content))
        }
        return indicators
    }
}

extension ScrollOffset {
    public static let zero = ScrollOffset(x: 0, y: 0)
}

extension Frame {
    /// The area both frames cover, or nil when they don't overlap. Frames that only touch along an edge don't.
    public func intersection(_ other: Frame) -> Frame? {
        guard intersects(other) else { return nil }
        let minX = Swift.max(x, other.x)
        let minY = Swift.max(y, other.y)
        return Frame(x: minX, y: minY, w: Swift.min(maxX, other.maxX) - minX, h: Swift.min(maxY, other.maxY) - minY)
    }
}
