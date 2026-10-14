import Foundation

/// The app-wide settings in `settings.json` (spec 3 and 12): the viewport new screens get, the grid size screens use
/// until they have their own, whether snapping starts on, the user's viewport presets, and keybind overrides. Each
/// starts at the value the app used before settings existed.
public struct AppSettings: Equatable, Sendable {
    /// The viewport a new screen gets.
    public enum DefaultViewport: Hashable, Sendable {
        /// A preset or custom size.
        case viewport(Viewport)
        /// The display the window is on, measured when the screen is created (spec 8.2).
        case thisDevice
    }

    public var defaultViewport: DefaultViewport
    /// The grid size of a screen whose editor state has none.
    public var gridSize: Int
    /// Whether snapping is on when a window opens.
    public var snapping: Bool
    public var viewportPresets: [ViewportPreset]
    /// Combinations that replace an action's defaults; an empty list leaves the action without a key.
    public var keybindOverrides: [KeyAction: [KeyCombo]] {
        didSet { keybinds = KeybindRegistry(overrides: keybindOverrides) }
    }
    /// The spec Section 9 defaults with the overrides on top.
    public private(set) var keybinds: KeybindRegistry

    public init(
        defaultViewport: DefaultViewport = .viewport(.defaultForNewScreens),
        gridSize: Int = Snapping.defaultGridSize,
        snapping: Bool = true,
        viewportPresets: [ViewportPreset] = [],
        keybindOverrides: [KeyAction: [KeyCombo]] = [:]
    ) {
        self.defaultViewport = defaultViewport
        self.gridSize = gridSize
        self.snapping = snapping
        self.viewportPresets = viewportPresets
        self.keybindOverrides = keybindOverrides
        keybinds = KeybindRegistry(overrides: keybindOverrides)
    }

    public static let defaults = AppSettings()

    /// The viewport for a new screen. This Device uses `displaySize`, or the built-in default when there is no
    /// display to measure.
    public func newScreenViewport(displaySize: (width: Double, height: Double)?) -> Viewport {
        switch defaultViewport {
        case .viewport(let viewport):
            return viewport
        case .thisDevice:
            guard let displaySize else { return .defaultForNewScreens }
            return ViewportPresets.thisDevice(width: displaySize.width, height: displaySize.height)
        }
    }

    public static func == (lhs: AppSettings, rhs: AppSettings) -> Bool {
        lhs.defaultViewport == rhs.defaultViewport && lhs.gridSize == rhs.gridSize && lhs.snapping == rhs.snapping
            && lhs.viewportPresets == rhs.viewportPresets && lhs.keybindOverrides == rhs.keybindOverrides
    }
}
