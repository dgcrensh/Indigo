import Foundation

public enum Geometry {
    /// The smallest width and height a region may have, in points (spec Section 5).
    public static let minimumSize = 4

    public static func meetsMinimumSize(_ frame: Frame) -> Bool {
        frame.w >= minimumSize && frame.h >= minimumSize
    }
}

extension Frame {
    /// A frame from fractional points, rounded to whole points. Gestures produce fractional values; the model
    /// stores whole points (spec 3.4). The far edges are rounded too, so the size is the difference of the rounded
    /// edges rather than a separately rounded size.
    public init(rounding x: Double, y: Double, w: Double, h: Double) {
        let minX = Int(x.rounded())
        let minY = Int(y.rounded())
        self.init(x: minX, y: minY, w: Int((x + w).rounded()) - minX, h: Int((y + h).rounded()) - minY)
    }
}
