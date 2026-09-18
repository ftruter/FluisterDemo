import Foundation
import Testing

struct ASREvalCSVTests {
    @Test func writesHeaderAndARow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let csv = try ASREvalCSV(folder: dir)
        try csv.append(
            index: 1,
            rate: .twice,
            durationSeconds: 15,
            wer: 0.125,
            temperature: 0,
            sourceWAVPath: "/tmp/clip.wav"
        )
        let text = try String(contentsOf: csv.url, encoding: .utf8)
        #expect(text.contains(ASREvalCSV.header))
        #expect(text.contains("1,2.00x,15.000,0.125000,0.000,/tmp/clip.wav"))
    }
}
