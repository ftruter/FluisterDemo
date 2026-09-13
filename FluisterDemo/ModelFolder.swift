import Foundation

/// WhisperKit Core ML folder produced by whisperkittools.
public struct ModelFolder: Equatable, Sendable {
    public static let requiredBundles = [
        "MelSpectrogram.mlmodelc",
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    public static let requiredFiles = [
        "tokenizer.json",
        "config.json",
    ]

    public static func isComplete(at url: URL, fileManager: FileManager = .default) -> Bool {
        for bundle in requiredBundles {
            var isDirectory: ObjCBool = false
            let path = url.appendingPathComponent(bundle, isDirectory: true)
            guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return false }
        }
        for file in requiredFiles {
            let path = url.appendingPathComponent(file)
            guard fileManager.fileExists(atPath: path.path) else { return false }
        }
        return true
    }
}

enum ModelBookmark {
    static let defaultsKey = "modelFolderBookmark"

    static func save(_ url: URL, defaults: UserDefaults = .standard) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: defaultsKey)
    }

    static func resolve(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope) {
            defaults.set(refreshed, forKey: defaultsKey)
        }
        return url
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
