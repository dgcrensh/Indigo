import Foundation

/// A rectangle on a screen with a title, a kind, and a description. A class so the canvas can hold its identity.
public final class Region {
    public let id: RegionID
    public var title: String
    public var kind: RegionKind
    public var frame: Frame
    public var description: String
    public var scroll: Scroll?
    public var links: [Link]
    /// Child regions in z-order: later children draw on top.
    public var children: [Region]

    public init(
        id: RegionID = .make(),
        title: String,
        kind: RegionKind = .open,
        frame: Frame,
        description: String = "",
        scroll: Scroll? = nil,
        links: [Link] = [],
        children: [Region] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.frame = frame
        self.description = description
        self.scroll = scroll
        self.links = links
        self.children = children
    }

    /// The area children must fit in: the frame, or the scrolling content area when the region scrolls.
    public var contentArea: Frame {
        guard let scroll else { return frame }
        return Frame(x: frame.x, y: frame.y, w: scroll.contentWidth, h: scroll.contentHeight)
    }

    /// A deep copy with the same IDs.
    public func copy() -> Region {
        Region(
            id: id,
            title: title,
            kind: kind,
            frame: frame,
            description: description,
            scroll: scroll,
            links: links,
            children: children.map { $0.copy() }
        )
    }

    /// This region and every descendant, depth first in sibling order.
    public var subtree: [Region] {
        [self] + children.flatMap(\.subtree)
    }
}
