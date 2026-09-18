import SwiftUI

struct PreparingModelView: View {
    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Preparing the model for this device", comment: "Full-pane title while Core ML compiles Fluister.")
                    .font(.title2)
                    .multilineTextAlignment(.center)
            }
        } description: {
            Text("Once, on this device. Start listening turns on when it is done.", comment: "Explains that Core ML compile is a one-time wait before listening.")
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PreparingModelView()
}
