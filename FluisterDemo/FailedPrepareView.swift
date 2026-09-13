import SwiftUI

struct FailedPrepareView: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        ContentUnavailableView {
            Label("Can't listen", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failureMessage)
        } actions: {
            Button("Try again", action: transcriber.retryPrepare)
                .buttonStyle(.borderedProminent)
            Button("Choose model…", action: transcriber.chooseModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureMessage: String {
        if case .failed(let message) = transcriber.phase {
            return message
        }
        return ""
    }
}
