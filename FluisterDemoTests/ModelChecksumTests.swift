import Foundation
import Testing
@testable import FluisterDemo

struct ModelChecksumTests {
    @Test func hashesASingleFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: file)
        #expect(try ModelChecksum.hashFile(file) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func treeHashMatchesConverterScript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appendingPathComponent("hello.txt"))
        #expect(try ModelChecksum.hashTree(root) == "b57c45bb4019f6ae092eb3bc19cdcdd3fd1f461971dc6219cd6a4e3b5b433523")
    }

    @Test func treeHashSortsRelativePaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("z", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("aa".utf8).write(to: root.appendingPathComponent("a.bin"))
        try Data("bb".utf8).write(to: nested.appendingPathComponent("b.bin"))
        #expect(try ModelChecksum.hashTree(root) == "cf3d535ff2b7d7af770fee1b683c507c5117dc7959ac39ff00826dcc840798cf")
    }

    @Test func verifyRejectsIncompleteFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(throws: ModelStoreError.incomplete) {
            try ModelChecksum.verify(folder: root, expected: [:])
        }
    }

    @Test func verifyRejectsMismatchedFileHash() throws {
        let root = try makeCompleteModelFolder()
        #expect(throws: ModelStoreError.checksumMismatch("config.json")) {
            try ModelChecksum.verify(folder: root, expected: ["config.json": "deadbeef"])
        }
    }
}

struct ModelInstallTests {
    @Test func promoteReplacesCurrentOnlyAfterStagingIsInPlace() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = try makeCompleteModelFolder(in: parent.appendingPathComponent("current"))
        try Data("old".utf8).write(to: current.appendingPathComponent("old-marker.txt"))
        let staging = try makeCompleteModelFolder(in: parent.appendingPathComponent("staging"))
        try Data("new".utf8).write(to: staging.appendingPathComponent("new-marker.txt"))

        try ModelInstall.promote(staging: staging, current: current)

        #expect(ModelFolder.isComplete(at: current))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("new-marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: current.appendingPathComponent("old-marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("current.outgoing").path))
    }

    @Test func failedVerifyDoesNotTouchCurrent() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = try makeCompleteModelFolder(in: parent.appendingPathComponent("current"))
        try Data("keep".utf8).write(to: current.appendingPathComponent("keep.txt"))
        let staging = parent.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        #expect(throws: ModelStoreError.incomplete) {
            try ModelChecksum.verify(folder: staging, expected: [:])
        }
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("keep.txt").path))
        #expect(ModelFolder.isComplete(at: current))
    }
}

func makeCompleteModelFolder(
    in root: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for bundle in ModelFolder.requiredBundles {
        let url = root.appendingPathComponent(bundle, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try Data([0x00]).write(to: url.appendingPathComponent("coremldata.bin"))
    }
    for file in ModelFolder.requiredFiles {
        try Data("{}".utf8).write(to: root.appendingPathComponent(file))
    }
    return root
}
