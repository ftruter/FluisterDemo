import Foundation
import Testing
@testable import FluisterDemo

struct ModelFileTransferTests {
    @Test func skipCompleteDestination() {
        #expect(ModelFileTransfer.plan(destSize: 100, partSize: 0, expected: 100) == .skip(100))
        #expect(ModelFileTransfer.plan(destSize: 100, partSize: 0, expected: nil) == .skip(100))
    }

    @Test func resumePartialPartFile() {
        #expect(ModelFileTransfer.plan(destSize: 0, partSize: 50, expected: 100) == .resume(from: 50))
        #expect(ModelFileTransfer.plan(destSize: 0, partSize: 50, expected: nil) == .resume(from: 50))
    }

    @Test func resumeTruncatedDestination() {
        #expect(ModelFileTransfer.plan(destSize: 40, partSize: 0, expected: 100) == .resume(from: 40))
    }

    @Test func freshDownloadWhenNothingOnDisk() {
        #expect(ModelFileTransfer.plan(destSize: 0, partSize: 0, expected: 100) == .download)
        #expect(ModelFileTransfer.plan(destSize: 0, partSize: 0, expected: nil) == .download)
    }

    @Test func existingBytesCountDestOrPartNotBoth() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dest = root.appendingPathComponent("a.bin")
        let part = root.appendingPathComponent("b.bin.part")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: dest)
        try Data(repeating: 2, count: 7).write(to: part)
        let bytes = ModelFileTransfer.existingBytes(
            in: root,
            files: ["a.bin", "b.bin"],
            prefix: ""
        )
        #expect(bytes == 17)
    }

    @Test func appendExtendsExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent("out.bin")
        let temp = root.appendingPathComponent("more.bin")
        try Data("ab".utf8).write(to: dest)
        try Data("cd".utf8).write(to: temp)
        try ModelFileTransfer.append(temp: temp, onto: dest)
        #expect(try String(contentsOf: dest, encoding: .utf8) == "abcd")
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }
}

struct StagingJobTests {
    @Test func roundTripsRevisionAndFiles() throws {
        let remote = RemoteModelInfo(
            repoID: "FTruter/fluister-turbo-coreml",
            revision: "abc",
            lastModified: Date(timeIntervalSince1970: 1_700_000_000),
            bytes: 50,
            files: ["fluister-turbo-v2/config.json"],
            sha256: ["config.json": "deadbeef"],
            packagePrefix: "fluister-turbo-v2"
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var job = StagingJob(from: remote)
        job.sizes["config.json"] = 12
        try job.save(in: root)
        let loaded = try #require(StagingJob.load(from: root))
        #expect(loaded.revision == "abc")
        #expect(loaded.packagePrefix == "fluister-turbo-v2")
        #expect(loaded.sizes["config.json"] == 12)
        #expect(loaded.remote.files == remote.files)
    }
}
