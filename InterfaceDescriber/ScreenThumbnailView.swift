import DescriberCore
import SwiftUI

/// A screen's miniature on its sidebar card: the sheet with its corners, and each region in its kind family's fill,
/// drawn from `ScreenThumbnail`. It reads only its own screen's thumbnail revision, so edits elsewhere don't redraw it.
struct ScreenThumbnailView: View {
    static let size = CGSize(width: 40, height: 72)

    let screen: Screen
    let revision: ThumbnailRevision
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let _ = revision.value
        let thumbnail = ScreenThumbnail.rects(
            for: screen, width: Double(Self.size.width), height: Double(Self.size.height))
        let palette = colorScheme == .dark ? PaperPalette.dark : PaperPalette.light
        Canvas { context, _ in
            let sheet = Path(
                roundedRect: Self.rect(thumbnail.sheet), cornerRadius: CGFloat(thumbnail.sheetRadius))
            context.fill(sheet, with: .color(Color(cgColor: palette.sheet.cgColor)))
            context.clip(to: sheet)
            for region in thumbnail.regions {
                let colors = palette.colors(for: region.family)
                let path = Path(Self.rect(region.frame))
                context.fill(path, with: .color(Color(cgColor: colors.fill.cgColor)))
                context.stroke(path, with: .color(Color(cgColor: colors.border.cgColor)), lineWidth: 0.5)
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
