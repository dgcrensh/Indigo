import Foundation

// On Apple platforms CGRect's geometry lives in CoreGraphics; on Linux, Foundation has it all.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The zoom and pan the canvas shows one screen with. `panX` and `panY` are the screen point at the view's
/// top-left corner, as in `ScreenEditorState`, so a view point is `(screen point − pan) × zoom`. View coordinates
/// grow down, like screen coordinates.
public struct Camera: Hashable, Sendable {
    public static let minimumZoom = 0.1
    public static let maximumZoom = 8.0
    /// The zoom levels Zoom In and Zoom Out step through.
    public static let zoomSteps = [0.1, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    public private(set) var zoom: Double
    public var panX: Double
    public var panY: Double

    public init(zoom: Double = 1, panX: Double = 0, panY: Double = 0) {
        self.zoom = Self.clamp(zoom)
        self.panX = panX
        self.panY = panY
    }

    public init(_ state: ScreenEditorState) {
        self.init(zoom: state.zoom, panX: state.panX, panY: state.panY)
    }

    /// `state` with this camera's zoom and pan, keeping its grid size and scroll offsets.
    public func applied(to state: ScreenEditorState) -> ScreenEditorState {
        var state = state
        state.zoom = zoom
        state.panX = panX
        state.panY = panY
        return state
    }

    public static func clamp(_ zoom: Double) -> Double {
        min(max(zoom, minimumZoom), maximumZoom)
    }

    // MARK: Converting

    public func viewPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - panX) * zoom, y: (point.y - panY) * zoom)
    }

    public func screenPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / zoom + panX, y: point.y / zoom + panY)
    }

    public func viewRect(fromScreen rect: CGRect) -> CGRect {
        CGRect(
            origin: viewPoint(fromScreen: rect.origin),
            size: CGSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    public func screenRect(fromView rect: CGRect) -> CGRect {
        CGRect(
            origin: screenPoint(fromView: rect.origin),
            size: CGSize(width: rect.width / zoom, height: rect.height / zoom))
    }

    /// The part of the screen a view of `viewSize` shows.
    public func visibleRect(viewSize: CGSize) -> CGRect {
        screenRect(fromView: CGRect(origin: .zero, size: viewSize))
    }

    // MARK: Changing

    /// Zoomed to `zoom` (clamped), keeping the screen point under the view point `anchor` where it is.
    public func zoomed(to zoom: Double, anchor: CGPoint) -> Camera {
        let fixed = screenPoint(fromView: anchor)
        let zoom = Self.clamp(zoom)
        return Camera(zoom: zoom, panX: fixed.x - anchor.x / zoom, panY: fixed.y - anchor.y / zoom)
    }

    /// Moved so the content follows a drag of `dx`, `dy` view points.
    public func panned(byViewDX dx: Double, dy: Double) -> Camera {
        Camera(zoom: zoom, panX: panX - dx / zoom, panY: panY - dy / zoom)
    }

    /// Zoomed to the next step up, about `anchor`.
    public func zoomedIn(anchor: CGPoint) -> Camera {
        let next = Self.zoomSteps.first { $0 > zoom * (1 + 1e-6) } ?? Self.maximumZoom
        return zoomed(to: next, anchor: anchor)
    }

    /// Zoomed to the next step down, about `anchor`.
    public func zoomedOut(anchor: CGPoint) -> Camera {
        let next = Self.zoomSteps.last { $0 < zoom * (1 - 1e-6) } ?? Self.minimumZoom
        return zoomed(to: next, anchor: anchor)
    }

    /// The camera that shows `rect` as large as fits in `viewSize` inside `padding` on every side, no larger than
    /// `maximumZoom`, centered.
    public static func fitting(
        _ rect: CGRect,
        viewSize: CGSize,
        padding: Double = 0,
        maximumZoom: Double = Camera.maximumZoom
    ) -> Camera {
        let available = CGSize(
            width: max(viewSize.width - 2 * padding, 1), height: max(viewSize.height - 2 * padding, 1))
        let zoom = min(
            available.width / max(rect.width, 1),
            available.height / max(rect.height, 1),
            maximumZoom
        )
        return centering(rect, viewSize: viewSize, zoom: zoom)
    }

    /// The camera at 100 % with `rect` centered in `viewSize`.
    public static func actualSize(centering rect: CGRect, viewSize: CGSize) -> Camera {
        centering(rect, viewSize: viewSize, zoom: 1)
    }

    private static func centering(_ rect: CGRect, viewSize: CGSize, zoom: Double) -> Camera {
        let zoom = clamp(zoom)
        return Camera(
            zoom: zoom,
            panX: rect.midX - viewSize.width / 2 / zoom,
            panY: rect.midY - viewSize.height / 2 / zoom
        )
    }
}
