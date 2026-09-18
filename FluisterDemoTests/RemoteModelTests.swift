import Foundation
import Testing
@testable import FluisterDemo

struct RemoteModelTests {
    @Test func decodesHubModelListing() throws {
        let json = """
        {
          "id": "FTruter/fluister-turbo-coreml",
          "sha": "5376331417ceea3c661397518598ded84f1e3d7b",
          "lastModified": "2026-09-17T22:14:27.000Z",
          "usedStorage": 1618283746,
          "siblings": [
            {"rfilename": "config.json"},
            {"rfilename": ".gitattributes"},
            {"rfilename": "README.md"},
            {"rfilename": "AudioEncoder.mlmodelc/weights/weight.bin"}
          ]
        }
        """.data(using: .utf8)!
        let model = try HubJSON.decoder.decode(HubModelDTO.self, from: json)
        #expect(model.id == "FTruter/fluister-turbo-coreml")
        #expect(model.sha == "5376331417ceea3c661397518598ded84f1e3d7b")
        #expect(model.usedStorage == 1_618_283_746)
        #expect(model.siblings.count == 4)
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: model.lastModified)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 17)
    }

    @Test func skipsDotFilesAndReadme() {
        #expect(!HuggingFaceModelCatalog.shouldDownload(".gitattributes"))
        #expect(!HuggingFaceModelCatalog.shouldDownload("README.md"))
        #expect(HuggingFaceModelCatalog.shouldDownload("config.json"))
        #expect(HuggingFaceModelCatalog.shouldDownload("AudioEncoder.mlmodelc/weights/weight.bin"))
        #expect(HuggingFaceModelCatalog.shouldDownload("NOTICE"))
    }

    @Test func nestedHubFolderIsThePackagePrefix() {
        let files = [
            "LICENSE",
            "README.md",
            "fluister-turbo-v2/config.json",
            "fluister-turbo-v2/AudioEncoder.mlmodelc/weights/weight.bin",
            "fluister-turbo-v2/manifest.json",
        ]
        #expect(HuggingFaceModelCatalog.packagePrefix(in: files) == "fluister-turbo-v2")
        #expect(!HuggingFaceModelCatalog.shouldDownload("LICENSE", prefix: "fluister-turbo-v2"))
        #expect(!HuggingFaceModelCatalog.shouldDownload("README.md", prefix: "fluister-turbo-v2"))
        #expect(HuggingFaceModelCatalog.shouldDownload("fluister-turbo-v2/config.json", prefix: "fluister-turbo-v2"))
        #expect(
            HuggingFaceModelCatalog.localPath(
                "fluister-turbo-v2/AudioEncoder.mlmodelc/weights/weight.bin",
                prefix: "fluister-turbo-v2"
            ) == "AudioEncoder.mlmodelc/weights/weight.bin"
        )
    }

    @Test func rootLayoutHasEmptyPackagePrefix() {
        let files = [
            "config.json",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "manifest.json",
        ]
        #expect(HuggingFaceModelCatalog.packagePrefix(in: files) == "")
        #expect(HuggingFaceModelCatalog.localPath("config.json", prefix: "") == "config.json")
    }

    @Test func resolveURLKeepsNestedPath() {
        let url = HuggingFaceModelCatalog.resolveURL(
            endpoint: "https://huggingface.co",
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "abc123",
            file: "AudioEncoder.mlmodelc/weights/weight.bin"
        )
        #expect(url?.absoluteString == "https://huggingface.co/FTruter/fluister-turbo-coreml/resolve/abc123/AudioEncoder.mlmodelc/weights/weight.bin")
    }

    @Test func decodesConverterManifest() throws {
        let json = """
        {
          "approxBytes": 1632428593,
          "sha256": {
            "config.json": "64f9be30c5dc6b20f44cb9b719a6cea34c12be3ccb99820bbf0ff2298ac773ec"
          }
        }
        """.data(using: .utf8)!
        let manifest = try HubJSON.decoder.decode(ConverterManifest.self, from: json)
        #expect(manifest.approxBytes == 1_632_428_593)
        #expect(manifest.sha256?["config.json"] == "64f9be30c5dc6b20f44cb9b719a6cea34c12be3ccb99820bbf0ff2298ac773ec")
    }
}

private struct FixedCatalog: ModelCatalog {
    var info: RemoteModelInfo
    func latest() async throws -> RemoteModelInfo { info }
}

struct ModelStoreFreshnessTests {
    @Test func missingLocalIsNotCurrent() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = FixedCatalog(info: RemoteModelInfo(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "abc",
            lastModified: Date(timeIntervalSince1970: 1_000),
            bytes: 1_600_000_000,
            files: ["config.json"],
            sha256: [:]
        ))
        let store = ModelStore(
            catalog: catalog,
            supportRoot: root,
            environment: [:],
            bundle: Bundle(for: ModelStore.self)
        )
        await store.refreshFromHub()
        #expect(store.remote?.revision == "abc")
        #expect(!store.hasLocal)
        #expect(!store.isCurrent)
        #expect(!store.isOutdated)
    }

    @Test func localWithoutRecordIsOutdatedOnceHubReplies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloaded = root.appendingPathComponent("Models/fluister-turbo-v2", isDirectory: true)
        _ = try makeCompleteModelFolder(in: downloaded)
        let catalog = FixedCatalog(info: RemoteModelInfo(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "new-sha",
            lastModified: Date(timeIntervalSince1970: 2_000),
            bytes: 1_600_000_000,
            files: ["config.json"],
            sha256: [:]
        ))
        let store = ModelStore(
            catalog: catalog,
            supportRoot: root,
            environment: [:],
            bundle: Bundle(for: ModelStore.self)
        )
        await store.refreshFromHub()
        #expect(store.hasLocal)
        #expect(store.isOutdated)
        #expect(!store.isCurrent)
        #expect(store.remote?.bytes == 1_600_000_000)
    }

    @Test func matchingRevisionIsCurrent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloaded = root.appendingPathComponent("Models/fluister-turbo-v2", isDirectory: true)
        _ = try makeCompleteModelFolder(in: downloaded)
        let modelsDir = root.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let record = InstalledModelRecord(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "same-sha",
            lastModified: Date(timeIntervalSince1970: 3_000),
            bytes: 1_600_000_000
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: modelsDir.appendingPathComponent("installed.json"))

        let catalog = FixedCatalog(info: RemoteModelInfo(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "same-sha",
            lastModified: Date(timeIntervalSince1970: 3_000),
            bytes: 1_600_000_000,
            files: ["config.json"],
            sha256: [:]
        ))
        let store = ModelStore(
            catalog: catalog,
            supportRoot: root,
            environment: [:],
            bundle: Bundle(for: ModelStore.self)
        )
        await store.refreshFromHub()
        #expect(store.hasLocal)
        #expect(store.isCurrent)
        #expect(!store.isOutdated)
    }

    @Test func environmentOverrideDoesNotOfferUpdate() async throws {
        let folder = try makeCompleteModelFolder()
        let catalog = FixedCatalog(info: RemoteModelInfo(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "newer",
            lastModified: Date(),
            bytes: 10,
            files: [],
            sha256: [:]
        ))
        let store = ModelStore(
            catalog: catalog,
            supportRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            environment: ["FLUISTER_MODEL_FOLDER": folder.path],
            bundle: Bundle(for: ModelStore.self)
        )
        await store.refreshFromHub()
        #expect(store.hasLocal)
        #expect(store.isCurrent)
        #expect(!store.isOutdated)
        #expect(store.usableFolder?.standardizedFileURL.path == folder.standardizedFileURL.path)
    }
}
