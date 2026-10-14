import DescriberCore
import SwiftUI

/// The `G` popover's content: a slider over the fixed grid steps (spec Section 9), on a Paper card.
struct GridSizePicker: View {
    let steps = Snapping.gridSteps
    @State private var index: Double
    let didPick: (Int) -> Void

    init(size: Int, didPick: @escaping (Int) -> Void) {
        let nearest = Snapping.gridSteps.indices.min {
            abs(Snapping.gridSteps[$0] - size) < abs(Snapping.gridSteps[$1] - size)
        }
        _index = State(initialValue: Double(nearest ?? 0))
        self.didPick = didPick
    }

    private var size: Int {
        steps[min(max(Int(index.rounded()), 0), steps.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Grid: \(size) pt")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Color(nsColor: .paper { $0.ink }))
            Slider(value: $index, in: 0...Double(steps.count - 1), step: 1)
                .tint(Color(nsColor: .paper { $0.accent }))
                .onChange(of: index) {
                    didPick(size)
                }
            HStack {
                ForEach(steps, id: \.self) { step in
                    Text("\(step)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color(nsColor: .paper { $0.secondaryInk }))
                    if step != steps.last {
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(Color(nsColor: .paper { $0.card }))
    }
}
