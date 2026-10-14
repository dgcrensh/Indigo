import Foundation

/// A rectangle in whole points, in absolute screen coordinates (spec 3.4).
public struct Frame: Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int

    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
    public var area: Int { w * h }

    /// Whether `other` lies entirely inside this frame. Touching edges count as inside.
    public func contains(_ other: Frame) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }

    /// This frame moved by a delta.
    public func offsetBy(dx: Int, dy: Int) -> Frame {
        Frame(x: x + dx, y: y + dy, w: w, h: h)
    }
}

/// The logical frame, in points, that a screen targets.
public struct Viewport: Hashable, Sendable {
    /// The preset the viewport came from, such as `iphone-15`, or nil for a custom size.
    public var preset: String?
    public var width: Int
    public var height: Int

    public init(preset: String? = nil, width: Int, height: Int) {
        self.preset = preset
        self.width = width
        self.height = height
    }

    /// The viewport new screens get when settings don't name another (`AppSettings.defaultViewport`).
    public static let defaultForNewScreens = Viewport(preset: "iphone-15", width: 393, height: 852)
}

public enum ScrollAxis: String, CaseIterable, Sendable {
    case vertical
    case horizontal
    case both
}

/// Scrolling content on a screen or region. The content area starts at the frame's origin (spec 3.4).
public struct Scroll: Hashable, Sendable {
    public var axis: ScrollAxis
    public var contentWidth: Int
    public var contentHeight: Int

    public init(axis: ScrollAxis, contentWidth: Int, contentHeight: Int) {
        self.axis = axis
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }
}

/// A reference from a region to another screen.
public struct Link: Hashable, Sendable {
    public var screen: ScreenID
    /// Free text describing what triggers the link, such as `click` or `right-click`.
    public var trigger: String?

    public init(screen: ScreenID, trigger: String? = nil) {
        self.screen = screen
        self.trigger = trigger
    }
}

/// Screens that are the same screen at different viewports.
public struct VariantGroup: Hashable, Sendable {
    public var name: String
    public var screens: [ScreenID]

    public init(name: String, screens: [ScreenID]) {
        self.name = name
        self.screens = screens
    }
}

/// What a screen represents: a full screen or one of the overlay kinds.
public enum ScreenKind: String, CaseIterable, Sendable {
    case screen
    case modal
    case sheet
    case popover
    case menu
    case alert
}

/// The optional kind of a region (spec 3.4). `open` is the default and is never written to a file.
public enum RegionKind: String, CaseIterable, Sendable {
    case open
    case container
    case text
    case image
    case button
    case input
    case toggle
    case picker
    case list
    case navigation
    case menuItem = "menu-item"
}
