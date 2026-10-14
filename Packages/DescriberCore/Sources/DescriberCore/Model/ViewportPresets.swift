import Foundation

/// A named viewport size: a built-in one or one the user saved (spec 8.2). Its `id` is what a screen's viewport
/// stores as `preset`.
public struct ViewportPreset: Hashable, Sendable {
    public var id: String
    public var name: String
    public var width: Int
    public var height: Int

    public init(id: String, name: String, width: Int, height: Int) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
    }

    /// A screen viewport at this preset's size.
    public var viewport: Viewport {
        Viewport(preset: id, width: width, height: height)
    }
}

/// The viewport choices: the built-in presets, This Device, Custom, and user presets from settings (spec 8.2).
public enum ViewportPresets {
    /// The `preset` of a viewport measured from the display the window was on.
    public static let thisDeviceID = "this-device"

    public static let builtIn: [ViewportPreset] = [
        ViewportPreset(id: "iphone-se", name: "iPhone SE", width: 375, height: 667),
        ViewportPreset(id: "iphone-15", name: "iPhone 15", width: 393, height: 852),
        ViewportPreset(id: "iphone-15-pro-max", name: "iPhone 15 Pro Max", width: 430, height: 932),
        ViewportPreset(id: "ipad", name: "iPad", width: 820, height: 1180),
        ViewportPreset(id: "ipad-pro-13", name: "iPad Pro 13-inch", width: 1032, height: 1376),
        ViewportPreset(id: "laptop", name: "Laptop", width: 1440, height: 900),
        ViewportPreset(id: "desktop", name: "Desktop", width: 1920, height: 1080),
    ]

    /// A This Device viewport for a display of `width` × `height` points, rounded to whole points.
    public static func thisDevice(width: Double, height: Double) -> Viewport {
        Viewport(
            preset: thisDeviceID, width: max(Int(width.rounded()), 1), height: max(Int(height.rounded()), 1))
    }

    /// The built-in or user preset with `id`.
    public static func preset(withID id: String, userPresets: [ViewportPreset] = []) -> ViewportPreset? {
        builtIn.first { $0.id == id } ?? userPresets.first { $0.id == id }
    }

    /// Such as "iPhone 15 — 393 × 852", "This Device — 1512 × 982" or "Custom — 500 × 400". A preset this build
    /// doesn't know, such as another Mac's user preset, shows its ID.
    public static func label(for viewport: Viewport, userPresets: [ViewportPreset] = []) -> String {
        let size = "\(viewport.width) × \(viewport.height)"
        guard let id = viewport.preset else { return "Custom — \(size)" }
        if id == thisDeviceID {
            return "This Device — \(size)"
        }
        return "\(preset(withID: id, userPresets: userPresets)?.name ?? id) — \(size)"
    }

    /// A short name for a viewport, such as "iPad", "This Device" or "500 × 400", which New Variant puts after the
    /// screen's name.
    public static func shortName(for viewport: Viewport, userPresets: [ViewportPreset] = []) -> String {
        if viewport.preset == thisDeviceID {
            return "This Device"
        }
        if let id = viewport.preset, let preset = preset(withID: id, userPresets: userPresets) {
            return preset.name
        }
        return "\(viewport.width) × \(viewport.height)"
    }

    /// The menu title of a preset, such as "iPhone 15 (393 × 852)".
    public static func menuTitle(for preset: ViewportPreset) -> String {
        "\(preset.name) (\(preset.width) × \(preset.height))"
    }

    /// User presets for `entries` (name, width, height) in order, with IDs from the slugs of their names, made
    /// unique against the built-in IDs, This Device, and each other.
    public static func userPresets(_ entries: [(name: String, width: Int, height: Int)]) -> [ViewportPreset] {
        var used = Set(builtIn.map(\.id) + [thisDeviceID])
        return entries.map { entry in
            let base = Slug.make(entry.name)
            var id = base
            var suffix = 2
            while used.contains(id) {
                id = "\(base)-\(suffix)"
                suffix += 1
            }
            used.insert(id)
            return ViewportPreset(id: id, name: entry.name, width: entry.width, height: entry.height)
        }
    }

    /// `presets` with one named `name` at `width` × `height`: a preset with the same name (ignoring case) takes the
    /// new size, otherwise the new one goes at the end. IDs are worked out again from the names.
    public static func saving(
        name: String, width: Int, height: Int, in presets: [ViewportPreset]
    ) -> [ViewportPreset] {
        var entries = presets.map { (name: $0.name, width: $0.width, height: $0.height) }
        if let index = entries.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            entries[index] = (name, width, height)
        } else {
            entries.append((name, width, height))
        }
        return userPresets(entries)
    }
}
