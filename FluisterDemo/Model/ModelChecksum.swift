import CryptoKit
import Foundation

/// SHA-256 of a file or of a Core ML bundle tree.
///
/// Tree hashes match `assemble_whisperkit_folder.py`: sorted relative POSIX
/// paths, each followed by a NUL, the file's hex digest, and another NUL.
nonisolated enum ModelChecksum {
    static func hashFile(_ url: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashTree(_ root: URL, fileManager: FileManager = .default) throws -> String {
        var hasher = SHA256()
        for file in try regularFiles(at: root, fileManager: fileManager) {
            let rel = file.path(relativeTo: root).replacingOccurrences(of: "\\", with: "/")
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(try hashFile(file).utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Confirms required WhisperKit pieces exist and, when `expected` is not
    /// empty, that each named path's hash matches the converter manifest.
    static func verify(
        folder: URL,
        expected: [String: String],
        fileManager: FileManager = .default
    ) throws {
        guard ModelFolder.isComplete(at: folder, fileManager: fileManager) else {
            throw ModelStoreError.incomplete
        }
        for (name, want) in expected.sorted(by: { $0.key < $1.key }) {
            let url = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw ModelStoreError.checksumMismatch(name)
            }
            let got = isDirectory.boolValue ? try hashTree(url, fileManager: fileManager) : try hashFile(url)
            if got != want {
                throw ModelStoreError.checksumMismatch(name)
            }
        }
    }

    private static func regularFiles(at root: URL, fileManager: FileManager) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted {
            $0.path(relativeTo: root) < $1.path(relativeTo: root)
        }
    }
}

nonisolated private extension URL {
    func path(relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let full = standardizedFileURL.path
        if full == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if full.hasPrefix(prefix) {
            return String(full.dropFirst(prefix.count))
        }
        return lastPathComponent
    }
}
