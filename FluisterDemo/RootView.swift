import SwiftUI

struct RootView: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        VStack(spacing: 0) {
            ListenControls()
            Divider()
            MainPane()
            Divider()
            StatusFooter()
            AttributionFooter()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 640, minHeight: 420)
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
