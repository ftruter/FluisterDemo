import SwiftUI

struct ModelUpdateBar: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        let models = transcriber.models
        if models.isDownloading, models.hasLocal {
            DownloadProgressView(
                downloadedBytes: models.downloadedBytes,
                expectedBytes: models.expectedBytes
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else if models.pendingPromote {
            Text("Update is ready. It applies when you stop listening.", comment: "Banner after a new Core ML package has been verified while a listen session is still using the old files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if models.isOutdated, !models.isDownloading {
            ModelUpdateButton(
                bytes: models.remote?.bytes,
                lastModified: models.remote?.lastModified,
                lastError: models.lastError,
                onUpdate: transcriber.downloadModel
            )
        }
    }
}

struct ModelUpdateButton: View {
    let bytes: Int64?
    let lastModified: Date?
    let lastError: String?
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onUpdate) {
                if let bytes, bytes > 0 {
                    Text("Update the speech recognition model (\(bytes, format: .byteCount(style: .file)))", comment: "Button when a newer Core ML package is on Hugging Face. The variable is the download size. Listening still works with the copy already on this device.")
                } else {
                    Text("Update the speech recognition model", comment: "Button when a newer Core ML package is on Hugging Face and the size is not known yet.")
                }
            }
            .buttonStyle(.bordered)
            if let lastModified {
                Text("Latest on Hugging Face: \(lastModified, format: .dateTime.day().month().year())", comment: "Caption under the update button. The variable is the Hub last-modified date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
