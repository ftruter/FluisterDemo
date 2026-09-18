import Foundation
import os
@testable import FluisterDemo

nonisolated enum AfrikaansASRLogging {
    static let log = Logger(subsystem: "truter.com.fluister.demo.tests", category: "AfrikaansASR")
}

nonisolated struct AfrikaansClip: Codable, Hashable, Sendable, Identifiable {
    var row: Int
    var audioId: String
    var chunkIndex: Int
    var transcript: String

    var id: String { "\(audioId)_chunk_\(String(format: "%04d", chunkIndex))" }
    var fileName: String { "\(id).wav" }
}

nonisolated struct AfrikaansClipManifest: Codable, Sendable {
    var dataset: String
    var config: String
    var split: String
    var revision: String?
    var seed: Int
    var selection: String
    var catalogSize: Int
    var catalogSpeakers: Int
    var clips: [AfrikaansClip]

    var speakers: Set<String> { Set(clips.map(\.audioId)) }

    static func load(fileManager: FileManager = .default) throws -> AfrikaansClipManifest {
        guard let url = manifestURL(fileManager: fileManager) else {
            throw AfrikaansClipError.missingManifest
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AfrikaansClipManifest.self, from: Data(contentsOf: url))
    }

    /// One clip from each speaker first, then fill from the remaining pool.
    func speakerDiverseSample(count: Int) -> [AfrikaansClip] {
        var seen = Set<String>()
        var sample: [AfrikaansClip] = []
        sample.reserveCapacity(min(count, clips.count))
        for clip in clips where seen.insert(clip.audioId).inserted {
            sample.append(clip)
            if sample.count == count { return sample }
        }
        for clip in clips where !sample.contains(clip) {
            sample.append(clip)
            if sample.count == count { return sample }
        }
        return sample
    }

    private static func manifestURL(fileManager: FileManager) -> URL? {
        let nearby = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/afrikaans-30s-train-500.json")
        if fileManager.fileExists(atPath: nearby.path) { return nearby }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(
                forResource: "afrikaans-30s-train-500",
                withExtension: "json",
                subdirectory: "Fixtures"
            ) ?? bundle.url(forResource: "afrikaans-30s-train-500", withExtension: "json") {
                return url
            }
        }
        return nil
    }
}

nonisolated enum AfrikaansClipCorpus: Sendable {
    static let minimumCount = 500
    static let skipNetworkEnvironmentKey = "FLUISTER_SKIP_NETWORK_TESTS"
    static let fullEvalEnvironmentKey = "FLUISTER_ASR_EVAL"
    static let downloadCorpusEnvironmentKey = "FLUISTER_DOWNLOAD_CORPUS"
    static let cacheEnvironmentKey = "FLUISTER_CLIP_CACHE"

    static var skipNetwork: Bool { truthy(ProcessInfo.processInfo.environment[skipNetworkEnvironmentKey]) }
    static var fullEval: Bool { truthy(ProcessInfo.processInfo.environment[fullEvalEnvironmentKey]) }
    static var downloadCorpus: Bool {
        fullEval || truthy(ProcessInfo.processInfo.environment[downloadCorpusEnvironmentKey])
    }

    nonisolated static func cacheRoot(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment[cacheEnvironmentKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return caches
            .appendingPathComponent("truter.com.fluister.demo.tests", isDirectory: true)
            .appendingPathComponent("afrikaans-30s", isDirectory: true)
    }

    nonisolated static func localURL(for clip: AfrikaansClip, fileManager: FileManager = .default) -> URL {
        cacheRoot(fileManager: fileManager).appendingPathComponent(clip.fileName)
    }

    /// 16 kHz mono 16-bit PCM × 30 s plus a WAV header, as published on the dataset.
    static let expectedWAVBytes = 960_078
    static let minimumWAVBytes = 800_000
    static let maximumWAVBytes = 1_200_000

    struct Inventory: Sendable {
        var folder: URL
        var fileCount: Int
        var totalBytes: Int

        var megabytes: String {
            String(format: "%.1f", Double(totalBytes) / 1_048_576)
        }

        var testerMessage: String {
            """
            Fluister test WAV cache (spot-check size and RIFF integrity here):
            \(folder.path)
            \(fileCount) files, \(megabytes) MB total.
            Each clip should be a ~960 KB 16 kHz mono 30 s WAV (dataset files are \(AfrikaansClipCorpus.expectedWAVBytes) bytes).
            """
        }
    }

    nonisolated static func inventory(fileManager: FileManager = .default) -> Inventory {
        let folder = cacheRoot(fileManager: fileManager)
        let files = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let wavs = files.filter { $0.pathExtension.lowercased() == "wav" }
        let total = wavs.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return Inventory(folder: folder, fileCount: wavs.count, totalBytes: total)
    }

    nonisolated static func announceCacheToTester(_ extra: String = "") {
        let message = inventory().testerMessage + (extra.isEmpty ? "" : "\n\(extra)")
        print(message)
        AfrikaansASRLogging.log.notice("\(message, privacy: .public)")
    }

    nonisolated static func validateWAV(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = values.fileSize ?? 0
        guard (minimumWAVBytes...maximumWAVBytes).contains(size) else {
            throw AfrikaansClipError.corruptWAV(url.lastPathComponent, size)
        }
        let header = try Data(contentsOf: url, options: [.mappedIfSafe]).prefix(12)
        guard header.starts(with: Data("RIFF".utf8)), header.suffix(4) == Data("WAVE".utf8) else {
            throw AfrikaansClipError.corruptWAV(url.lastPathComponent, size)
        }
    }

    nonisolated static func ensureLocalFiles(
        for clips: [AfrikaansClip],
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) async throws -> [AfrikaansClip: URL] {
        try fileManager.createDirectory(at: cacheRoot(fileManager: fileManager), withIntermediateDirectories: true)
        var result: [AfrikaansClip: URL] = [:]
        result.reserveCapacity(clips.count)
        var missing: [AfrikaansClip] = []
        let root = cacheRoot(fileManager: fileManager)
        AfrikaansASRLogging.log.notice("clip cache \(root.path, privacy: .public) — \(clips.count) requested")
        announceCacheToTester("Need \(clips.count) clips for this run.")
        for clip in clips {
            let url = localURL(for: clip, fileManager: fileManager)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try validateWAV(url)
                } catch {
                    AfrikaansASRLogging.log.error("dropping corrupt cache \(clip.id, privacy: .public): \(String(describing: error), privacy: .public)")
                    try? fileManager.removeItem(at: url)
                    missing.append(clip)
                    continue
                }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                AfrikaansASRLogging.log.info("cache hit \(clip.id, privacy: .public) \(url.path, privacy: .public) \(size) bytes")
                result[clip] = url
            } else {
                missing.append(clip)
            }
        }
        guard !missing.isEmpty else {
            AfrikaansASRLogging.log.notice("all \(clips.count) clips already cached")
            return result
        }

        AfrikaansASRLogging.log.notice("downloading \(missing.count) wav files from andreoosthuizen/afrikaans-30s")
        let remote = try await resolveAudioURLs(for: missing, session: session)
        for (index, clip) in missing.enumerated() {
            if index > 0 {
                try await Task.sleep(nanoseconds: 80_000_000)
            }
            guard let audioURL = remote[clip] else {
                throw AfrikaansClipError.missingAudio(clip.id)
            }
            let dest = localURL(for: clip, fileManager: fileManager)
            AfrikaansASRLogging.log.info("download \(index + 1)/\(missing.count) \(clip.id, privacy: .public) from \(audioURL.host ?? "huggingface", privacy: .public) -> \(dest.path, privacy: .public)")
            let saved = try await saveDownload(
                from: audioURL,
                to: dest,
                fileManager: fileManager,
                session: session
            )
            try validateWAV(saved)
            let size = (try? saved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            AfrikaansASRLogging.log.info("wrote \(clip.id, privacy: .public) \(size) bytes")
            result[clip] = saved
        }
        announceCacheToTester("Download pass finished (\(missing.count) new files).")
        return result
    }

    /// Page the datasets-server rows API (100 rows per call) instead of one request per clip.
    nonisolated static func resolveAudioURLs(
        for clips: [AfrikaansClip],
        session: URLSession = .shared
    ) async throws -> [AfrikaansClip: URL] {
        let pages = Dictionary(grouping: clips) { $0.row / 100 }
        var result: [AfrikaansClip: URL] = [:]
        result.reserveCapacity(clips.count)
        for page in pages.keys.sorted() {
            let offset = page * 100
            AfrikaansASRLogging.log.info("catalog page offset=\(offset)")
            let payload = try await fetchRows(offset: offset, length: 100, session: session)
            let byRow = Dictionary(uniqueKeysWithValues: payload.rows.map { ($0.rowIdx, $0) })
            for clip in pages[page] ?? [] {
                guard let envelope = byRow[clip.row] else {
                    throw AfrikaansClipError.missingRow(clip.row)
                }
                guard envelope.row.audioId == clip.audioId, envelope.row.chunkIndex == clip.chunkIndex else {
                    throw AfrikaansClipError.rowMismatch(clip.id)
                }
                guard let src = envelope.row.audio.first?.src, let url = URL(string: src) else {
                    throw AfrikaansClipError.missingAudio(clip.id)
                }
                result[clip] = url
            }
        }
        return result
    }

    nonisolated static func saveDownload(
        from audioURL: URL,
        to dest: URL,
        fileManager: FileManager,
        session: URLSession
    ) async throws -> URL {
        let (temp, response) = try await fetchDownload(audioURL, session: session)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AfrikaansClipError.downloadFailed(dest.lastPathComponent, http.statusCode)
        }
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.moveItem(at: temp, to: dest)
        return dest
    }
}

private nonisolated func fetchRows(offset: Int, length: Int, session: URLSession) async throws -> RowsPayload {
    var components = URLComponents(string: "https://datasets-server.huggingface.co/rows")!
    components.queryItems = [
        URLQueryItem(name: "dataset", value: "andreoosthuizen/afrikaans-30s"),
        URLQueryItem(name: "config", value: "default"),
        URLQueryItem(name: "split", value: "train"),
        URLQueryItem(name: "offset", value: String(offset)),
        URLQueryItem(name: "length", value: String(length)),
    ]
    guard let url = components.url else { throw AfrikaansClipError.missingManifest }
    let (data, response) = try await fetchData(url, session: session)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw AfrikaansClipError.catalogFailed(http.statusCode)
    }
    return try JSONDecoder().decode(RowsPayload.self, from: data)
}

nonisolated enum ClipHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    static let retryableURLErrors: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost,
        .notConnectedToInternet,
        .dnsLookupFailed,
        .cannotConnectToHost,
        .cannotFindHost,
        .resourceUnavailable,
        .dataNotAllowed,
    ]
}

private nonisolated func hubRequest(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("fluister-demo-tests/1.0", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 180
    if let token = ProcessInfo.processInfo.environment["HF_TOKEN"]
        ?? ProcessInfo.processInfo.environment["HUGGING_FACE_HUB_TOKEN"],
       !token.isEmpty
    {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
}

private nonisolated func fetchData(_ url: URL, session: URLSession) async throws -> (Data, URLResponse) {
    let session = session === URLSession.shared ? ClipHTTP.session : session
    return try await retrying {
        try await session.data(for: hubRequest(url))
    }
}

private nonisolated func fetchDownload(_ url: URL, session: URLSession) async throws -> (URL, URLResponse) {
    let session = session === URLSession.shared ? ClipHTTP.session : session
    return try await retrying {
        try await session.download(for: hubRequest(url))
    }
}

private nonisolated func retrying<T>(
    attempts: Int = 8,
    operation: () async throws -> (T, URLResponse)
) async throws -> (T, URLResponse) {
    var delay: UInt64 = 2_000_000_000
    var lastError: Error?
    for attempt in 1...attempts {
        do {
            let result = try await operation()
            if let http = result.1 as? HTTPURLResponse, [429, 500, 502, 503].contains(http.statusCode) {
                AfrikaansASRLogging.log.error("HTTP \(http.statusCode) attempt \(attempt)/\(attempts), retry in \(delay / 1_000_000_000)s")
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 32_000_000_000)
                lastError = AfrikaansClipError.catalogFailed(http.statusCode)
                continue
            }
            return result
        } catch let error as URLError where ClipHTTP.retryableURLErrors.contains(error.code) {
            AfrikaansASRLogging.log.error("\(error.code.rawValue) \(error.localizedDescription, privacy: .public) attempt \(attempt)/\(attempts), retry in \(delay / 1_000_000_000)s")
            lastError = error
            try await Task.sleep(nanoseconds: delay)
            delay = min(delay * 2, 32_000_000_000)
        }
    }
    throw lastError ?? AfrikaansClipError.catalogFailed(-1)
}

nonisolated enum AfrikaansClipError: Error, CustomStringConvertible {
    case missingManifest
    case downloadFailed(String, Int)
    case catalogFailed(Int)
    case missingRow(Int)
    case rowMismatch(String)
    case missingAudio(String)
    case corruptWAV(String, Int)

    var description: String {
        switch self {
        case .missingManifest: "Afrikaans clip manifest is missing from the test bundle."
        case let .downloadFailed(id, code): "Download of \(id) failed (\(code))."
        case let .catalogFailed(code): "Hugging Face rows API failed (\(code))."
        case let .missingRow(row): "No dataset row at offset \(row)."
        case let .rowMismatch(id): "Dataset row no longer matches \(id)."
        case let .missingAudio(id): "Dataset row for \(id) has no audio URL."
        case let .corruptWAV(name, size): "\(name) is not a valid 30s WAV (\(size) bytes)."
        }
    }
}

private nonisolated struct RowsPayload: Decodable {
    var rows: [RowEnvelope]
}

private nonisolated struct RowEnvelope: Decodable {
    var rowIdx: Int
    var row: Row

    enum CodingKeys: String, CodingKey {
        case rowIdx = "row_idx"
        case row
    }
}

private nonisolated struct Row: Decodable {
    var audioId: String
    var chunkIndex: Int
    var audio: [AudioAsset]

    enum CodingKeys: String, CodingKey {
        case audioId = "audio_id"
        case chunkIndex = "chunk_index"
        case audio
    }
}

private nonisolated struct AudioAsset: Decodable {
    var src: String
}

nonisolated func truthy(_ value: String?) -> Bool {
    guard let value else { return false }
    switch value.lowercased() {
    case "1", "true", "yes", "on": return true
    default: return false
    }
}
