import Foundation

/// Append-only eval table so a stopped run still has rows to mine.
final class ASREvalCSV: @unchecked Sendable {
    static let fileName = "fluister-asr-eval.csv"
    static let header = "Index,Rate,Duration(s),WER,Temperature,SourceWAVPath"

    let url: URL
    private let handle: FileHandle

    static func path(fileManager: FileManager = .default) -> URL {
        AfrikaansClipCorpus.cacheRoot(fileManager: fileManager).appendingPathComponent(fileName)
    }

    init(folder: URL? = nil, fileManager: FileManager = .default) throws {
        let folder = folder ?? AfrikaansClipCorpus.cacheRoot(fileManager: fileManager)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent(Self.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        fileManager.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try writeLine(Self.header)
        announce()
    }

    func append(
        index: Int,
        rate: SpeechRate,
        durationSeconds: Double,
        wer: Double,
        temperature: Float,
        sourceWAVPath: String
    ) throws {
        let line = [
            String(index),
            csvField(rate.rawValue),
            String(format: "%.3f", durationSeconds),
            String(format: "%.6f", wer),
            String(format: "%.3f", temperature),
            csvField(sourceWAVPath),
        ].joined(separator: ",")
        try writeLine(line)
    }

    deinit {
        try? handle.close()
    }

    private func writeLine(_ line: String) throws {
        try handle.write(contentsOf: Data((line + "\n").utf8))
        try handle.synchronize()
    }

    private func announce() {
        let message = """
            Fluister ASR eval CSV (mine high WER vs rate, then open SourceWAVPath):
            \(url.path)
            Columns: \(Self.header)
            Rows are flushed after every clip/rate so a stopped run is still usable.
            """
        print(message)
        AfrikaansASRLogging.log.notice("\(message, privacy: .public)")
    }
}

private func csvField(_ value: String) -> String {
    if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}
