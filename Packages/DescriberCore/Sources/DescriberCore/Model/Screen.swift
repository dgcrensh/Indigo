import Foundation
import Observation

/// One canvas with a target viewport, saved as its own file in the package.
@Observable
public final class Screen {
    public let id: ScreenID
    public var name: String
    public var kind: ScreenKind
    public var viewport: Viewport
    public var scroll: Scroll?
    /// Top-level regions in z-order: later regions draw on top.
    public var regions: [Region]

    public init(
        id: ScreenID = .make(),
        name: String,
        kind: ScreenKind = .screen,
        viewport: Viewport,
        scroll: Scroll? = nil,
        regions: [Region] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.viewport = viewport
        self.scroll = scroll
        self.regions = regions
    }

    /// Every region on the screen, depth first in sibling order.
    public var allRegions: [Region] {
        Region.depthFirst(regions)
    }

    /// A deep copy with the same IDs.
    public func copy() -> Screen {
        Screen(
            id: id,
            name: name,
            kind: kind,
            viewport: viewport,
            scroll: scroll,
            regions: regions.map { $0.copy() }
        )
    }
}
