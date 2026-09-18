import Foundation

nonisolated enum ModelInstall {
    /// Replace `current` with a verified `staging` folder. The live folder is
    /// moved aside first and only deleted after the new copy is in place.
    static func promote(
        staging: URL,
        current: URL,
        fileManager: FileManager = .default
    ) throws {
        let parent = current.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let backup = parent.appendingPathComponent("\(current.lastPathComponent).outgoing")
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        if fileManager.fileExists(atPath: current.path) {
            try fileManager.moveItem(at: current, to: backup)
            do {
                try fileManager.moveItem(at: staging, to: current)
            } catch {
                try? fileManager.moveItem(at: backup, to: current)
                throw error
            }
            try fileManager.removeItem(at: backup)
        } else {
            try fileManager.moveItem(at: staging, to: current)
        }
    }
}

nonisolated enum ModelFileTransfer {
    enum Plan: Equatable {
        case skip(Int64)
        case download
        case resume(from: Int64)
    }

    static func plan(destSize: Int64, partSize: Int64, expected: Int64?) -> Plan {
        if destSize > 0 {
            if let expected, destSize < expected {
                return .resume(from: destSize)
            }
            return .skip(destSize)
        }
        if partSize > 0 { return .resume(from: partSize) }
        return .download
    }

    static func fileSize(_ url: URL, fileManager: FileManager = .default) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    static func existingBytes(in folder: URL, files: [String], prefix: String, fileManager: FileManager = .default) -> Int64 {
        var total: Int64 = 0
        for hubPath in files {
            let local = HuggingFaceModelCatalog.localPath(hubPath, prefix: prefix)
            let dest = folder.appendingPathComponent(local)
            let part = dest.appendingPathExtension("part")
            let destSize = fileSize(dest, fileManager: fileManager)
            if destSize > 0 {
                total += destSize
            } else {
                total += fileSize(part, fileManager: fileManager)
            }
        }
        return total
    }

    static func append(temp: URL, onto dest: URL, fileManager: FileManager = .default) throws {
        if !fileManager.fileExists(atPath: dest.path) {
            try fileManager.moveItem(at: temp, to: dest)
            return
        }
        let reader = try FileHandle(forReadingFrom: temp)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: dest)
        defer { try? writer.close() }
        try writer.seekToEnd()
        while true {
            let chunk = try reader.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            try writer.write(contentsOf: chunk)
        }
        try fileManager.removeItem(at: temp)
    }
}

nonisolated struct StagingJob: Codable, Equatable, Sendable {
    var repoID: String
    var revision: String
    var lastModified: Date
    var bytes: Int64
    var files: [String]
    var sha256: [String: String]
    var packagePrefix: String
    var sizes: [String: Int64]

    init(from remote: RemoteModelInfo, sizes: [String: Int64] = [:]) {
        repoID = remote.repoID
        revision = remote.revision
        lastModified = remote.lastModified
        bytes = remote.bytes
        files = remote.files
        sha256 = remote.sha256
        packagePrefix = remote.packagePrefix
        self.sizes = sizes
    }

    var remote: RemoteModelInfo {
        RemoteModelInfo(
            repoID: repoID,
            revision: revision,
            lastModified: lastModified,
            bytes: bytes,
            files: files,
            sha256: sha256,
            packagePrefix: packagePrefix
        )
    }

    static func url(in staging: URL) -> URL {
        staging.appendingPathComponent("download.json")
    }

    static func load(from staging: URL, fileManager: FileManager = .default) -> StagingJob? {
        let url = Self.url(in: staging)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StagingJob.self, from: data)
    }

    func save(in staging: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url(in: staging), options: .atomic)
    }
}

/// Long-lived background session so a 1.5 GB model keeps downloading after Home.
nonisolated final class ModelDownloadRuntime: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let sessionIdentifier = "truter.com.fluister.demo.model"
    static let shared = ModelDownloadRuntime()

    private let lock = NSLock()
    private var urlSession: URLSession!
    private var continuation: CheckedContinuation<(URL, Int), Error>?
    private var destination: URL?
    private var already: Int64 = 0
    private var total: Int64 = 0
    private var lastPublish = Date.distantPast
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    var backgroundCompletion: (() -> Void)?

    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 12
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func setProgress(_ progress: @escaping @Sendable (Int64, Int64) -> Void) {
        lock.lock()
        self.progress = progress
        lock.unlock()
    }

    func setTotals(already: Int64, total: Int64) {
        lock.lock()
        self.already = already
        self.total = total
        lock.unlock()
    }

    func download(from url: URL, rangeStart: Int64, to part: URL) async throws -> (URL, Int) {
        var request = URLRequest(url: url)
        request.setValue("FluisterDemo/1.0", forHTTPHeaderField: "User-Agent")
        if rangeStart > 0 {
            request.setValue("bytes=\(rangeStart)-", forHTTPHeaderField: "Range")
        }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            continuation = cont
            destination = part
            lock.unlock()
            let task = urlSession.downloadTask(with: request)
            task.taskDescription = "\(rangeStart)\t\(part.path)"
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date()
        lock.lock()
        let skip = now.timeIntervalSince(lastPublish) <= 0.2
            && totalBytesWritten != totalBytesExpectedToWrite
        if !skip { lastPublish = now }
        let already = already
        let total = total
        let progress = progress
        lock.unlock()
        guard !skip else { return }
        progress?(already + totalBytesWritten, max(total, already + totalBytesWritten))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 416, !(200..<300).contains(status) {
            resumeContinuation(throwing: ModelStoreError.http(status))
            return
        }
        lock.lock()
        let dest = destination
        let waiting = continuation != nil
        lock.unlock()
        do {
            if waiting {
                guard let dest else {
                    resumeContinuation(throwing: ModelStoreError.incomplete)
                    return
                }
                if status == 416 {
                    resumeContinuation(returning: (dest, status))
                    return
                }
                let copy = dest.appendingPathExtension("transfer")
                if FileManager.default.fileExists(atPath: copy.path) {
                    try FileManager.default.removeItem(at: copy)
                }
                try FileManager.default.copyItem(at: location, to: copy)
                resumeContinuation(returning: (copy, status))
            } else {
                try settleOrphan(task: downloadTask, location: location, status: status)
            }
        } catch {
            resumeContinuation(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resumeContinuation(throwing: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async {
            handler?()
        }
    }

    private func settleOrphan(task: URLSessionDownloadTask, location: URL, status: Int) throws {
        guard let description = task.taskDescription else { return }
        let parts = description.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let rangeStart = Int64(parts[0]) else { return }
        let part = URL(fileURLWithPath: String(parts[1]))
        let fm = FileManager.default
        try fm.createDirectory(at: part.deletingLastPathComponent(), withIntermediateDirectories: true)
        if status == 416 { return }
        let copy = part.appendingPathExtension("transfer")
        if fm.fileExists(atPath: copy.path) {
            try fm.removeItem(at: copy)
        }
        try fm.copyItem(at: location, to: copy)
        if status == 206, rangeStart > 0 {
            try ModelFileTransfer.append(temp: copy, onto: part, fileManager: fm)
        } else {
            if fm.fileExists(atPath: part.path) {
                try fm.removeItem(at: part)
            }
            try fm.moveItem(at: copy, to: part)
        }
    }

    private func resumeContinuation(returning value: (URL, Int)) {
        lock.lock()
        let cont = continuation
        continuation = nil
        destination = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    private func resumeContinuation(throwing error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        destination = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

nonisolated final class ModelFileDownloader: @unchecked Sendable {
    private let runtime: ModelDownloadRuntime
    private let progress: @Sendable (Int64, Int64) -> Void

    init(
        runtime: ModelDownloadRuntime = .shared,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.runtime = runtime
        self.progress = progress
        runtime.setProgress(progress)
    }

    func download(remote: RemoteModelInfo, to folder: URL, endpoint: String) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var already = ModelFileTransfer.existingBytes(
            in: folder,
            files: remote.files,
            prefix: remote.packagePrefix,
            fileManager: fm
        )
        let total = max(remote.bytes, already)
        runtime.setTotals(already: already, total: total)
        progress(already, total)

        var job = StagingJob.load(from: folder) ?? StagingJob(from: remote)
        if job.revision != remote.revision {
            try fm.removeItem(at: folder)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            job = StagingJob(from: remote)
            already = 0
            runtime.setTotals(already: 0, total: max(remote.bytes, 0))
            progress(0, max(remote.bytes, 0))
        }
        try job.save(in: folder)

        for relative in remote.files {
            try Task.checkCancellation()
            guard let url = HuggingFaceModelCatalog.resolveURL(
                endpoint: endpoint,
                repoID: remote.repoID,
                revision: remote.revision,
                file: relative
            ) else {
                throw ModelStoreError.unreachable
            }
            let local = HuggingFaceModelCatalog.localPath(relative, prefix: remote.packagePrefix)
            let dest = folder.appendingPathComponent(local)
            let part = dest.appendingPathExtension("part")
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

            let destSize = ModelFileTransfer.fileSize(dest, fileManager: fm)
            let partSize = ModelFileTransfer.fileSize(part, fileManager: fm)
            let expected = job.sizes[local]
            switch ModelFileTransfer.plan(destSize: destSize, partSize: partSize, expected: expected) {
            case .skip:
                continue
            case .download:
                try await fetch(url: url, onto: part, dest: dest, rangeStart: 0, local: local, job: &job, folder: folder)
            case .resume(let from):
                if destSize > 0, partSize == 0 {
                    try fm.moveItem(at: dest, to: part)
                }
                try await fetch(url: url, onto: part, dest: dest, rangeStart: from, local: local, job: &job, folder: folder)
            }
            already = ModelFileTransfer.existingBytes(
                in: folder,
                files: remote.files,
                prefix: remote.packagePrefix,
                fileManager: fm
            )
            runtime.setTotals(already: already, total: max(remote.bytes, already))
            progress(already, max(remote.bytes, already))
        }
    }

    private func fetch(
        url: URL,
        onto part: URL,
        dest: URL,
        rangeStart: Int64,
        local: String,
        job: inout StagingJob,
        folder: URL
    ) async throws {
        let (temp, status) = try await runtime.download(from: url, rangeStart: rangeStart, to: part)
        defer { try? FileManager.default.removeItem(at: temp) }
        let fm = FileManager.default
        if status == 416 {
            if ModelFileTransfer.fileSize(part, fileManager: fm) == 0, rangeStart > 0 {
                throw ModelStoreError.http(416)
            }
        } else if status == 206, rangeStart > 0 {
            try ModelFileTransfer.append(temp: temp, onto: part, fileManager: fm)
        } else {
            if fm.fileExists(atPath: part.path) {
                try fm.removeItem(at: part)
            }
            try fm.moveItem(at: temp, to: part)
        }
        let size = ModelFileTransfer.fileSize(part, fileManager: fm)
        if size > 0 {
            job.sizes[local] = max(job.sizes[local] ?? 0, size)
            try job.save(in: folder)
        }
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: part, to: dest)
    }
}
