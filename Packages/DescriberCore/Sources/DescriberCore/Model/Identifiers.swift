import Foundation

/// A screen's identity. Stored as a lowercase UUID string; files refer to screens only by ID, never by file name.
public struct ScreenID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    /// A new random ID.
    public static func make() -> ScreenID {
        ScreenID(UUID().uuidString)
    }

    public var description: String { rawValue }

    public static func < (lhs: ScreenID, rhs: ScreenID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A region's identity. Stored as a lowercase UUID string and unique across the whole project.
public struct RegionID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    /// A new random ID.
    public static func make() -> RegionID {
        RegionID(UUID().uuidString)
    }

    public var description: String { rawValue }

    public static func < (lhs: RegionID, rhs: RegionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
