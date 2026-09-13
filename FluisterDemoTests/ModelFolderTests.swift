import Foundation
import Testing
@testable import FluisterDemo

struct ModelFolderTests {
    @Test func incompleteFolderIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(!ModelFolder.isComplete(at: root))
    }

    @Test func completeFolderIsAccepted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        for bundle in ModelFolder.requiredBundles {
            let url = root.appendingPathComponent(bundle, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            try Data([0x00]).write(to: url.appendingPathComponent("coremldata.bin"))
        }
        for file in ModelFolder.requiredFiles {
            try Data("{}".utf8).write(to: root.appendingPathComponent(file))
        }
        #expect(ModelFolder.isComplete(at: root))
    }
}
