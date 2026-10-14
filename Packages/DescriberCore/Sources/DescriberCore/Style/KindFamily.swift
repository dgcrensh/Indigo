import Foundation

/// The five groups the eleven region kinds share colors in, since eleven colors are too many to tell apart. The kind
/// itself is still named in the details panel.
public enum KindFamily: String, CaseIterable, Sendable {
    case neutral
    case structure
    case content
    case action
    case input
}

extension RegionKind {
    /// The family whose colors regions of this kind are drawn in.
    public var family: KindFamily {
        switch self {
        case .open: .neutral
        case .container, .list, .navigation: .structure
        case .text, .image: .content
        case .button, .menuItem: .action
        case .input, .toggle, .picker: .input
        }
    }

    /// Whether regions of this kind are drawn without a fill, only their border, so paragraphs don't turn into slabs.
    public var isUnfilled: Bool {
        self == .text
    }
}
