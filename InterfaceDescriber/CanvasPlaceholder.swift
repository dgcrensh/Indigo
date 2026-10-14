import DescriberCore
import SwiftUI

/// Stands in for the canvas until milestone 4 draws it: names the active screen, its kind and viewport.
struct CanvasPlaceholder: View {
    var model: DocumentModel

    var body: some View {
        VStack(spacing: 6) {
            if let screen = model.activeScreen {
                Text(screen.name)
                    .font(.title2)
                Text(Self.summary(of: screen))
                    .foregroundStyle(.secondary)
            } else {
                Text("No screen")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Such as "screen, 393 × 852 pt (iphone-15)".
    static func summary(of screen: Screen) -> String {
        let viewport = screen.viewport
        var summary = "\(screen.kind.rawValue), \(viewport.width) × \(viewport.height) pt"
        if let preset = viewport.preset {
            summary += " (\(preset))"
        }
        return summary
    }
}
