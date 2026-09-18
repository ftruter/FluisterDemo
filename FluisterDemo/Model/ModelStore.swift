import Foundation

nonisolated enum ModelStoreError: Error, Equatable {
    case unreachable
    case http(Int)
    case malformedCatalog
    case incomplete
    case checksumMismatch(String)
    case missingRemote
}

@MainActor
@Observable
final class ModelStore {
    private(set) var remote: RemoteModelInfo?
    private(set) var installed: InstalledModelRecord?
    private(set) var isChecking = false
    private(set) var isDownloading = false
    private(set) var downloadedBytes: Int64 = 0
    private(set) var lastError: String?
    private(set) var pendingPromote = false
    private var inFlightDownload: Task<Void, Error>?

    let catalog: any ModelCatalog
    let endpoint: String
    let fileManager: FileManager
    let supportRoot: URL
    private let usingEnvOverride: Bool
    private let envFolder: URL?
    private let searchLegacyDocuments: Bool

    init(
        catalog: any ModelCatalog = HuggingFaceModelCatalog(),
        endpoint: String = HuggingFaceModelCatalog.defaultEndpoint,
        fileManager: FileManager = .default,
        supportRoot: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) {
        self.catalog = catalog
        self.endpoint = endpoint
        self.fileManager = fileManager
        self.searchLegacyDocuments = supportRoot == nil
        if let supportRoot {
            self.supportRoot = supportRoot
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let id = bundle.bundleIdentifier ?? "truter.com.fluister.demo"
            self.supportRoot = appSupport.appendingPathComponent(id, isDirectory: true)
        }
        if let env = environment["FLUISTER_MODEL_FOLDER"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if ModelFolder.isComplete(at: url, fileManager: fileManager) {
                envFolder = url
                usingEnvOverride = true
            } else {
                envFolder = nil
                usingEnvOverride = false
            }
        } else {
            envFolder = nil
            usingEnvOverride = false
        }
        installed = Self.readInstalled(at: installedRecordURL, fileManager: fileManager)
    }

    var downloadedFolder: URL {
        supportRoot
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("fluister-turbo-v2", isDirectory: true)
    }

    var stagingFolder: URL {
        supportRoot
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("fluister-turbo-v2.incoming", isDirectory: true)
    }

    private var installedRecordURL: URL {
        supportRoot
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("installed.json")
    }

    /// Folder WhisperKit can load right now, if any.
    var usableFolder: URL? {
        if let envFolder { return envFolder }
        if ModelFolder.isComplete(at: downloadedFolder, fileManager: fileManager) {
            return downloadedFolder
        }
        if searchLegacyDocuments,
           let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        {
            let leftover = documents.appendingPathComponent("fluister-turbo-v2", isDirectory: true)
            if ModelFolder.isComplete(at: leftover, fileManager: fileManager) {
                return leftover
            }
        }
        return nil
    }

    var hasLocal: Bool { usableFolder != nil }

    var isCurrent: Bool {
        if usingEnvOverride { return true }
        guard hasLocal, let remote else { return hasLocal && installed != nil }
        if let installed, installed.revision == remote.revision { return true }
        return false
    }

    var isOutdated: Bool {
        hasLocal && remote != nil && !isCurrent && !usingEnvOverride
    }

    var expectedBytes: Int64 {
        remote?.bytes ?? installed?.bytes ?? 0
    }

    /// A previous download left files in staging for the Hub revision we still want.
    var hasIncompleteDownload: Bool {
        guard !usingEnvOverride else { return false }
        guard let job = StagingJob.load(from: stagingFolder, fileManager: fileManager) else { return false }
        if let remote, job.revision != remote.revision { return false }
        return !ModelFolder.isComplete(at: stagingFolder, fileManager: fileManager)
    }

    func refreshFromHub() async {
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        do {
            let info = try await catalog.latest()
            remote = info
            if let job = StagingJob.load(from: stagingFolder, fileManager: fileManager),
               job.revision != info.revision
            {
                try? fileManager.removeItem(at: stagingFolder)
            }
            try promoteVerifiedStagingIfNeeded()
            if hasIncompleteDownload {
                downloadedBytes = ModelFileTransfer.existingBytes(
                    in: stagingFolder,
                    files: info.files,
                    prefix: info.packagePrefix,
                    fileManager: fileManager
                )
            }
        } catch {
            if !hasLocal {
                lastError = (error as? ModelStoreError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Downloads into staging and verifies checksums. Does not touch the live folder.
    /// Safe to call again: finished files are skipped and `.part` files resume with HTTP Range.
    func downloadToStaging() async throws {
        guard !usingEnvOverride else { return }
        if let inFlightDownload {
            try await inFlightDownload.value
            return
        }
        let task = Task { try await performDownload() }
        inFlightDownload = task
        defer { inFlightDownload = nil }
        try await task.value
    }

    private func performDownload() async throws {
        let info: RemoteModelInfo
        if let remote {
            info = remote
        } else {
            info = try await catalog.latest()
            remote = info
        }
        isDownloading = true
        lastError = nil
        downloadedBytes = ModelFileTransfer.existingBytes(
            in: stagingFolder,
            files: info.files,
            prefix: info.packagePrefix,
            fileManager: fileManager
        )
        let downloader = ModelFileDownloader { [weak self] written, _ in
            Task { @MainActor in
                self?.downloadedBytes = written
            }
        }
        defer { isDownloading = false }
        do {
            let staging = stagingFolder
            try await downloader.download(remote: info, to: staging, endpoint: endpoint)
            let expected = info.sha256
            try await Task.detached {
                try ModelChecksum.verify(folder: staging, expected: expected)
            }.value
            try? fileManager.removeItem(at: StagingJob.url(in: staging))
            pendingPromote = fileManager.fileExists(atPath: downloadedFolder.path)
                && ModelFolder.isComplete(at: downloadedFolder, fileManager: fileManager)
            downloadedBytes = max(info.bytes, downloadedBytes)
        } catch let error as ModelStoreError {
            if case .checksumMismatch(let name) = error {
                try? fileManager.removeItem(at: stagingFolder.appendingPathComponent(name))
            }
            lastError = error.message
            throw error
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Move verified staging onto the live folder. Safe only when WhisperKit
    /// is not reading the live folder (not listening).
    func promoteStaging() throws -> URL {
        let info = try requiredRemote()
        try ModelChecksum.verify(folder: stagingFolder, expected: info.sha256)
        try ModelInstall.promote(
            staging: stagingFolder,
            current: downloadedFolder,
            fileManager: fileManager
        )
        let record = InstalledModelRecord(
            repoID: info.repoID,
            revision: info.revision,
            lastModified: info.lastModified,
            bytes: info.bytes
        )
        try writeInstalled(record)
        installed = record
        pendingPromote = false
        lastError = nil
        return downloadedFolder
    }

    func applyStagingIfIdle(isListening: Bool) throws -> URL? {
        guard fileManager.fileExists(atPath: stagingFolder.path) else { return nil }
        guard let remote else { return nil }
        do {
            try ModelChecksum.verify(folder: stagingFolder, expected: remote.sha256)
        } catch {
            return nil
        }
        if isListening {
            pendingPromote = hasLocal
            return nil
        }
        return try promoteStaging()
    }

    private func promoteVerifiedStagingIfNeeded() throws {
        _ = try applyStagingIfIdle(isListening: false)
    }

    private func requiredRemote() throws -> RemoteModelInfo {
        if let remote { return remote }
        throw ModelStoreError.missingRemote
    }

    private func writeInstalled(_ record: InstalledModelRecord) throws {
        let parent = installedRecordURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: installedRecordURL, options: .atomic)
    }

    private static func readInstalled(at url: URL, fileManager: FileManager) -> InstalledModelRecord? {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InstalledModelRecord.self, from: data)
    }
}

extension ModelStoreError {
    var message: String {
        switch self {
        case .unreachable:
            String(localized: "Can't reach Hugging Face. Connect to the internet and try again.", comment: "Error when the model catalog cannot be loaded.")
        case .http(let code):
            String(localized: "Model download failed (\(code)).", comment: "HTTP error while downloading the Core ML model. The variable is the status code.")
        case .malformedCatalog:
            String(localized: "The Hugging Face model listing could not be read.", comment: "Error when the Hub JSON is unexpected.")
        case .incomplete:
            String(localized: "The downloaded Fluister model is missing files.", comment: "Error when the Core ML folder failed the completeness check.")
        case .checksumMismatch:
            String(localized: "The downloaded Fluister model did not match its checksums. The copy already on this device was left as-is.", comment: "Error when SHA-256 verification failed; old files are kept.")
        case .missingRemote:
            String(localized: "Can't reach Hugging Face. Connect to the internet and try again.", comment: "Error when the model catalog cannot be loaded.")
        }
    }
}
