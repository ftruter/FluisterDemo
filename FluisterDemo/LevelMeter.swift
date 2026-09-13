import SwiftUI

struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(4, proxy.size.width * CGFloat(level)))
            }
        }
        .accessibilityHidden(true)
    }
}
