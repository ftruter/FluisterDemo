import SwiftUI

struct RootView: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        VStack(spacing: 0) {
            ModelUpdateBar()
            Divider()
            MainPane()
            ListenBar()
        }
        .background(Color(.systemBackground))
        .task { transcriber.prepareIfNeeded() }
    }
}

struct MainPane: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        switch transcriber.phase {
        case .missingModel:
            MissingModelView()
        case .preparing:
            PreparingModelView()
        case .failed:
            FailedPrepareView()
        case .ready, .listening:
            TranscriptPane()
        }
    }
}

#Preview {
    RootView()
        .environment(Transcriber())
}
