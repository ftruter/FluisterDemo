import SwiftUI

struct StatusFooter: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !transcriber.modelDisplayName.isEmpty {
                Text(transcriber.modelDisplayName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var indicatorColor: Color {
        switch transcriber.phase {
        case .listening: .green
        case .preparing: .orange
        case .failed: .red
        case .missingModel: .yellow
        case .ready: .secondary
        }
    }

    private var statusText: String {
        let bundle = transcriber.language.bundle
        return switch transcriber.phase {
        case .ready:
            String(localized: "Ready. Audio stays on this device.", bundle: bundle, comment: "Idle status.")
        case .missingModel:
            String(localized: "Download the speech recognition model to begin.", bundle: bundle, comment: "Status when no local Core ML package is on the device.")
        case .preparing:
            String(localized: "Preparing the model for this device", bundle: bundle, comment: "Full-pane title while Core ML compiles Fluister.")
        case .listening:
            if transcriber.waitingForSpeech {
                String(localized: "Waiting for speech…", bundle: bundle, comment: "Status while the microphone is live but no voice has been heard yet.")
            } else {
                String(localized: "Listening…", bundle: bundle, comment: "Status while the microphone is live.")
            }
        case .failed(let message):
            message
        }
    }
}

#Preview {
    StatusFooter()
        .environment(Transcriber())
}
