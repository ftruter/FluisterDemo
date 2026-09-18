import SwiftUI

struct MissingModelView: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        let models = transcriber.models
        ContentUnavailableView {
            Label("No Fluister model", systemImage: "waveform")
        } description: {
            MissingModelDescription(
                isChecking: models.isChecking,
                lastModified: models.remote?.lastModified,
                lastError: models.lastError
            )
        } actions: {
            MissingModelActions(
                isChecking: models.isChecking,
                isDownloading: models.isDownloading,
                downloadedBytes: models.downloadedBytes,
                expectedBytes: models.expectedBytes,
                remoteBytes: models.remote?.bytes,
                onDownload: transcriber.downloadModel,
                onRetry: transcriber.retryPrepare
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MissingModelDescription: View {
    let isChecking: Bool
    let lastModified: Date?
    let lastError: String?

    var body: some View {
        VStack(spacing: 8) {
            if isChecking {
                Text("Looking up the latest model on Hugging Face…", comment: "Status while the app asks Hugging Face for the Core ML package date and size.")
            } else {
                Text("Fluister needs the on-device speech model before it can listen. Audio stays on this device.", comment: "Explains why the download is required when no local model exists.")
                if let lastModified {
                    Text("Latest on Hugging Face: \(lastModified, format: .dateTime.day().month().year())", comment: "Caption under the download button. The variable is the Hub last-modified date.")
                }
            }
            if let lastError, !lastError.isEmpty {
                Text(lastError)
                    .foregroundStyle(.red)
            }
        }
        .font(.body)
        .multilineTextAlignment(.center)
    }
}

struct MissingModelActions: View {
    let isChecking: Bool
    let isDownloading: Bool
    let downloadedBytes: Int64
    let expectedBytes: Int64
    let remoteBytes: Int64?
    let onDownload: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if isDownloading {
            DownloadProgressView(downloadedBytes: downloadedBytes, expectedBytes: expectedBytes)
        } else if isChecking {
            ProgressView()
                .controlSize(.large)
        } else {
            Button(action: onDownload) {
                if let remoteBytes, remoteBytes > 0 {
                    Text("Download the speech recognition model (\(remoteBytes, format: .byteCount(style: .file)))", comment: "Primary button when no local model exists. The variable is the Hub package size.")
                } else {
                    Text("Download the speech recognition model", comment: "Primary button when no local model exists and the Hub size is not known yet.")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Try again", action: onRetry)
        }
    }
}

struct DownloadProgressView: View {
    let downloadedBytes: Int64
    let expectedBytes: Int64

    var body: some View {
        VStack(spacing: 8) {
            if expectedBytes > 0 {
                ProgressView(value: Double(downloadedBytes), total: Double(expectedBytes))
                    .frame(maxWidth: 280)
                Text("Downloading \(downloadedBytes, format: .byteCount(style: .file)) of \(expectedBytes, format: .byteCount(style: .file))", comment: "Download progress. The first variable is bytes received, the second is the total.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Downloading the speech recognition model…", comment: "Indeterminate download progress.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    MissingModelView()
        .environment(Transcriber())
}
