import Foundation

nonisolated struct RemoteModelInfo: Equatable, Sendable {
    var repoID: String
    var revision: String
    var lastModified: Date
    var bytes: Int64
    /// Hub paths, including `packagePrefix` when the WhisperKit folder is nested.
    var files: [String]
    var sha256: [String: String]
    /// Empty when the Core ML tree sits at the repo root; `fluister-turbo-v2` after the Hub nest.
    var packagePrefix: String = ""
}

nonisolated protocol ModelCatalog: Sendable {
    func latest() async throws -> RemoteModelInfo
}

/// Hugging Face Hub catalog for the published WhisperKit / Core ML tree.
nonisolated struct HuggingFaceModelCatalog: ModelCatalog {
    static let defaultRepoID = "FTruter/fluister-turbo-coreml"
    static let defaultEndpoint = "https://huggingface.co"

    var repoID: String
    var endpoint: String
    var session: URLSession

    init(
        repoID: String = HuggingFaceModelCatalog.defaultRepoID,
        endpoint: String = HuggingFaceModelCatalog.defaultEndpoint,
        session: URLSession = .shared
    ) {
        self.repoID = repoID
        self.endpoint = endpoint
        self.session = session
    }

    func latest() async throws -> RemoteModelInfo {
        let model = try await fetchModel()
        let names = model.siblings.map(\.rfilename)
        let prefix = Self.packagePrefix(in: names)
        let manifest = try await fetchManifest(revision: model.sha, prefix: prefix)
        let files = names.filter { Self.shouldDownload($0, prefix: prefix) }
        let bytes = model.usedStorage ?? manifest.approxBytes ?? 0
        return RemoteModelInfo(
            repoID: model.id,
            revision: model.sha,
            lastModified: model.lastModified,
            bytes: bytes,
            files: files,
            sha256: manifest.sha256 ?? [:],
            packagePrefix: prefix
        )
    }

    /// Hub folder that contains `config.json` and the Core ML bundles.
    static func packagePrefix(in files: [String]) -> String {
        let names = Set(files)
        if names.contains("config.json") { return "" }
        for file in files where file.hasSuffix("/config.json") {
            let prefix = String(file.dropLast("/config.json".count))
            guard !prefix.isEmpty else { continue }
            let encoder = "\(prefix)/AudioEncoder.mlmodelc"
            if files.contains(where: { $0 == encoder || $0.hasPrefix(encoder + "/") }) {
                return prefix
            }
        }
        return ""
    }

    static func localPath(_ hubPath: String, prefix: String) -> String {
        guard !prefix.isEmpty else { return hubPath }
        let root = prefix + "/"
        if hubPath.hasPrefix(root) {
            return String(hubPath.dropFirst(root.count))
        }
        return hubPath
    }

    static func shouldDownload(_ relativePath: String, prefix: String = "") -> Bool {
        if relativePath.hasPrefix(".") { return false }
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        if name == "README.md" { return false }
        if prefix.isEmpty { return true }
        return relativePath.hasPrefix(prefix + "/")
    }

    static func resolveURL(endpoint: String, repoID: String, revision: String, file: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = file.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "\(endpoint)/\(repoID)/resolve/\(revision)/\(encoded)")
    }

    private func fetchModel() async throws -> HubModelDTO {
        guard let url = URL(string: "\(endpoint)/api/models/\(repoID)") else {
            throw ModelStoreError.unreachable
        }
        let data = try await get(url)
        do {
            return try HubJSON.decoder.decode(HubModelDTO.self, from: data)
        } catch {
            throw ModelStoreError.malformedCatalog
        }
    }

    private func fetchManifest(revision: String, prefix: String) async throws -> ConverterManifest {
        let file = prefix.isEmpty ? "manifest.json" : "\(prefix)/manifest.json"
        guard let url = Self.resolveURL(
            endpoint: endpoint,
            repoID: repoID,
            revision: revision,
            file: file
        ) else {
            throw ModelStoreError.unreachable
        }
        let data = try await get(url)
        return (try? HubJSON.decoder.decode(ConverterManifest.self, from: data)) ?? ConverterManifest()
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("FluisterDemo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelStoreError.unreachable
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ModelStoreError.http(http.statusCode)
        }
        return data
    }
}

nonisolated enum HubJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            if let date = basic.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO-8601 date: \(raw)")
            )
        }
        return decoder
    }()
}

nonisolated struct HubModelDTO: Decodable, Equatable {
    var id: String
    var sha: String
    var lastModified: Date
    var usedStorage: Int64?
    var siblings: [HubSiblingDTO]
}

nonisolated struct HubSiblingDTO: Decodable, Equatable {
    var rfilename: String
}

nonisolated struct ConverterManifest: Decodable, Equatable {
    var approxBytes: Int64?
    var sha256: [String: String]?
}

nonisolated struct InstalledModelRecord: Codable, Equatable, Sendable {
    var repoID: String
    var revision: String
    var lastModified: Date
    var bytes: Int64
}
