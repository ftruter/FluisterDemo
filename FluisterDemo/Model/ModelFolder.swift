import Foundation

/// WhisperKit Core ML folder produced by whisperkittools.
nonisolated public struct ModelFolder: Equatable, Sendable {
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

    /// Locations the app and tests try, in order.
    public static func discover(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        nearbyFrom sourceFile: String = #filePath
    ) -> URL? {
        if let env = environment["FLUISTER_MODEL_FOLDER"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if isComplete(at: url, fileManager: fileManager) { return url }
        }
        let folders: [FileManager.SearchPathDirectory] = [.documentDirectory, .applicationSupportDirectory]
        for directory in folders {
            let root = fileManager.urls(for: directory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            let bundledID = bundle.bundleIdentifier ?? "truter.com.fluister.demo"
            let candidates = [
                root.appendingPathComponent("fluister-turbo-v2", isDirectory: true),
                root.appendingPathComponent(bundledID, isDirectory: true)
                    .appendingPathComponent("fluister-turbo-v2", isDirectory: true),
            ]
            if let found = candidates.first(where: { isComplete(at: $0, fileManager: fileManager) }) {
                return found
            }
        }

        if let resource = bundle.resourceURL?
            .appendingPathComponent("fluister-turbo-v2", isDirectory: true),
           isComplete(at: resource, fileManager: fileManager)
        {
            return resource
        }

        #if DEBUG
        if let nearby = nearbyConversionOutput(from: sourceFile),
           isComplete(at: nearby, fileManager: fileManager)
        {
            return nearby
        }
        #endif
        return nil
    }

    #if DEBUG
    static func nearbyConversionOutput(from sourceFile: String) -> URL? {
        var url = URL(fileURLWithPath: sourceFile)
        url.deleteLastPathComponent()
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("FluisterTV/Tools/convert/out/fluister-turbo-v2", isDirectory: true)
            if isComplete(at: candidate) { return candidate }
        }
        return nil
    }
    #endif
}


