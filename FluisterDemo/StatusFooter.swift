import SwiftUI

struct StatusFooter: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
        switch transcriber.phase {
        case .ready:
            String(localized: "Ready. Audio stays on this Mac.", comment: "Idle status.")
        case .missingModel:
            String(localized: "Choose the Fluister Core ML folder to begin.", comment: "Status when no model is selected.")
        case .preparing:
            String(localized: "Preparing model on this Mac…", comment: "Status while Core ML compiles or loads.")
        case .listening:
            String(localized: "Listening…", comment: "Status while the microphone is live.")
        case .failed(let message):
            message
        }
    }
}
