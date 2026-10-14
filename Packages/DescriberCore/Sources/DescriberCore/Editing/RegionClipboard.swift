import Foundation

/// Regions copied with Cmd-C or Cmd-D, ready to paste onto any screen (spec Section 7). The app keeps them on the
/// pasteboard as `data(in:)`, so they can be pasted into another window or document.
public struct RegionClipboard {
    /// The name decoding errors give for the clipboard's JSON.
    static let fileName = "clipboard"

    /// The screen the regions were copied from.
    public let sourceScreen: ScreenID
    /// Copies of the copied regions, topmost only and in draw order; their children come with them.
    public let regions: [Region]

    /// Copies the selected regions on `screen`. A selected region inside another selected region comes with its
    /// ancestor rather than on its own. Nil when nothing selected is on the screen.
    public init?(copying selection: [RegionID], on screen: Screen) {
        let index = RegionIndex(screen: screen)
        let selected = Set(selection)
        let roots = index.regions.filter { region in
            selected.contains(region.id) && !index.isInside(region.id, anyOf: selected)
        }
        guard !roots.isEmpty else { return nil }
        sourceScreen = screen.id
        regions = roots.map { $0.copy() }
    }

    /// Reads clipboard data written by `data(in:)`. Throws a `FormatError` for anything else.
    public init(data: Data) throws {
        let contents = try ProjectDecoding.clipboard(data)
        guard !contents.regions.isEmpty else {
            throw FormatError.malformedJSON(file: Self.fileName, detail: "no regions")
        }
        sourceScreen = contents.screen
        regions = contents.regions
    }

    /// The regions as JSON, in the screen file's region format.
    public func data(in project: Project) -> Data {
        OrderedJSONWriter.data(
            .object([
                ("screen", .string(sourceScreen.rawValue)),
                ("regions", .array(regions.map { ProjectEncoding.region($0, in: project) })),
            ]))
    }

    /// The copied titles, one per line, for pasting as text elsewhere.
    public var text: String {
        regions.map(\.title).joined(separator: "\n")
    }

    /// The command that pastes copies of the regions onto `screen`, with new IDs (`PasteRegions` makes them).
    /// Links to screens `project` doesn't have, as when pasting from another document, are dropped. Copies of regions
    /// that are on `screen` start where those regions are drawn at the screen's scroll positions, `scrollOffsets`.
    /// While a copy would land exactly on a region drawn with the same frame, as when pasting onto the screen the
    /// regions came from or duplicating, all copies move one `grid` step right and down, so they show beside what is
    /// there.
    public func paste(
        onto screen: Screen, in project: Project, grid: Int, actionName: String = "Paste",
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) -> PasteRegions {
        let screens = Set(project.screens.map(\.id))
        let layout = ScrollLayout(screen: screen, offsets: scrollOffsets)
        let occupied = Set(layout.index.regions.compactMap { layout.drawnFrame(of: $0.id) })
        let drawn = regions.map { region -> Region in
            let copy = region.copy()
            if let frame = layout.drawnFrame(of: region.id), layout.index.region(region.id)?.frame == region.frame {
                let dx = frame.x - region.frame.x
                let dy = frame.y - region.frame.y
                for part in copy.subtree {
                    part.frame = part.frame.offsetBy(dx: dx, dy: dy)
                }
            }
            return copy
        }
        let step = max(grid, 1)
        var offset = 0
        // Bounded so a screen filled with regions on every step can't loop for long.
        while offset < 100 * step,
            drawn.contains(where: { occupied.contains($0.frame.offsetBy(dx: offset, dy: offset)) })
        {
            offset += step
        }
        for copy in drawn {
            for part in copy.subtree {
                part.frame = part.frame.offsetBy(dx: offset, dy: offset)
                part.links = part.links.filter { screens.contains($0.screen) }
            }
        }
        return PasteRegions(screen: screen.id, regions: drawn, actionName: actionName, scrollOffsets: scrollOffsets)
    }
}
