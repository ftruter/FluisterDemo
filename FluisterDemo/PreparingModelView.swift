import SwiftUI

struct PreparingModelView: View {
    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Preparing the model for this Mac", comment: "Full-pane title while Core ML compiles Fluister.")
            }
        } description: {
            Text("Once, on this Mac. Listen turns on when it is done.", comment: "Explains that Core ML compile is a one-time wait before listening.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
