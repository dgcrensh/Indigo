import DescriberCore
import SwiftUI

/// A screen's miniature on its sidebar card: the sheet with its corners, and each region in its kind family's fill,
/// drawn from `ScreenThumbnail`. It reads only its own screen's thumbnail revision, so edits elsewhere don't redraw it,
/// and the revision keeps the rectangles, so a redraw at the same revision doesn't compute them again.
struct ScreenThumbnailView: View {
    static let size = CGSize(width: 40, height: 72)

    let screen: Screen
    let revision: ThumbnailRevision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let thumbnail = revision.thumbnail(
            for: screen, width: Double(Self.size.width), height: Double(Self.size.height))
        let palette = colorScheme == .dark ? PaperPalette.dark : PaperPalette.light
        Canvas { context, _ in
            let sheet = Path(
                roundedRect: Self.rect(thumbnail.sheet), cornerRadius: CGFloat(thumbnail.sheetRadius))
            context.fill(sheet, with: .color(Color(cgColor: palette.sheet.cgColor)))
            context.clip(to: sheet)
            // Each family's colors are resolved once per draw, not once per rectangle.
            var shadings: [KindFamily: (fill: GraphicsContext.Shading, border: GraphicsContext.Shading)] = [:]
            for region in thumbnail.regions {
                let shading: (fill: GraphicsContext.Shading, border: GraphicsContext.Shading)
                if let resolved = shadings[region.family] {
                    shading = resolved
                } else {
                    let colors = palette.colors(for: region.family)
                    shading = (
                        .color(Color(cgColor: colors.fill.cgColor)), .color(Color(cgColor: colors.border.cgColor))
                    )
                    shadings[region.family] = shading
                }
                let path = Path(Self.rect(region.frame))
                context.fill(path, with: shading.fill)
                context.stroke(path, with: shading.border, lineWidth: 0.5)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: CGFloat(thumbnail.sheetRadius))
                .strokeBorder(Color(cgColor: palette.sheetBorder.cgColor), lineWidth: 0.5)
                .frame(width: CGFloat(thumbnail.sheet.w), height: CGFloat(thumbnail.sheet.h))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }

    private static func rect(_ rect: ThumbnailRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
    }
}
