import Foundation

/// Editor-only state saved in `.editor-state.json`: things that matter to the editor but not to readers of the
/// description (spec 3.1).
public struct EditorState: Hashable, Sendable {
    public var screens: [ScreenID: ScreenEditorState]
    /// Regions whose descriptions are shown on the canvas.
    public var visibleDescriptions: Set<RegionID>
    public var lastActiveScreen: ScreenID?

    public init(
        screens: [ScreenID: ScreenEditorState] = [:],
        visibleDescriptions: Set<RegionID> = [],
        lastActiveScreen: ScreenID? = nil
    ) {
        self.screens = screens
        self.visibleDescriptions = visibleDescriptions
        self.lastActiveScreen = lastActiveScreen
    }

    public var isEmpty: Bool {
        self == EditorState()
    }
}

/// Per-screen editor state.
public struct ScreenEditorState: Hashable, Sendable {
    public var zoom: Double
    public var panX: Double
    public var panY: Double
    /// Grid size in points, or nil for the app default.
    public var gridSize: Int?
    /// Scroll offsets inside scrollable regions, in points.
    public var scrollOffsets: [RegionID: ScrollOffset]

    public init(
        zoom: Double = 1,
        panX: Double = 0,
        panY: Double = 0,
        gridSize: Int? = nil,
        scrollOffsets: [RegionID: ScrollOffset] = [:]
    ) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.gridSize = gridSize
        self.scrollOffsets = scrollOffsets
    }
}

public struct ScrollOffset: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}
