import Foundation
import Testing
@testable import FluisterDemo

struct AfrikaansClipCorpusTests {
    @Test func selectedClipsCoverFiveHundredSpeakersDiverseSources() throws {
        let manifest = try AfrikaansClipManifest.load()
        #expect(manifest.dataset == "andreoosthuizen/afrikaans-30s")
        #expect(manifest.split == "train")
        #expect(manifest.selection == "round-robin-by-audio-id")
        #expect(manifest.clips.count >= AfrikaansClipCorpus.minimumCount)
        #expect(manifest.speakers.count == manifest.catalogSpeakers)
        #expect(manifest.speakers.count > 1)

        let ids = Set(manifest.clips.map(\.id))
        #expect(ids.count == manifest.clips.count)

        for clip in manifest.clips {
            #expect(!clip.audioId.isEmpty)
            #expect(clip.chunkIndex >= 0)
            #expect(clip.row >= 0)
            #expect(clip.transcript.split(whereSeparator: \.isWhitespace).count >= 1)
        }
    }

    @Test func dropsMicrophoneNoiseAndSingingClips() throws {
        let manifest = try AfrikaansClipManifest.load()
        let ids = Set(manifest.clips.map(\.id))
        let unusable = [
            "7nTZk7-XQFo-067_chunk_0010",
            "PZiQ2TRLiuU_chunk_0126",
            "WylbZD0lBys_chunk_0063",
            "vUMDANFSHp4_004_chunk_0023",
        ] + (2...18).map { String(format: "vUMDANFSHp4_003_chunk_%04d", $0) }
        for id in unusable {
            #expect(!ids.contains(id), "\(id) is microphone noise and/or singing")
        }
    }

    @Test func speakerDiverseSamplePicksDistinctSourcesFirst() throws {
        let manifest = try AfrikaansClipManifest.load()
        let sample = manifest.speakerDiverseSample(count: min(manifest.speakers.count, 8))
        #expect(Set(sample.map(\.audioId)).count == sample.count)
        #expect(sample.allSatisfy { manifest.clips.contains($0) })
    }

    @Test func cacheLivesOutsideTheRepo() {
        let cache = AfrikaansClipCorpus.cacheRoot()
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(!cache.path.hasPrefix(repo.path + "/"))
        #expect(!cache.path.contains("/FluisterDemoTests/"))
    }

    @Test func wavCacheFolderIsPrintedForSpotChecks() throws {
        let inventory = AfrikaansClipCorpus.inventory()
        AfrikaansClipCorpus.announceCacheToTester()
        Attachment.record(inventory.testerMessage, named: "wav-cache-folder.txt")
        #expect(!inventory.folder.path.isEmpty, Comment(rawValue: inventory.testerMessage))
        #expect(!inventory.folder.path.contains("/FluisterDemoTests/"))
    }
}

@Suite(.serialized)
struct AfrikaansClipDownloadTests {
    @Test func downloadsASingleSelectedClip() async throws {
        try skipIfNetworkDisabled()
        let clip = try #require(try AfrikaansClipManifest.load().clips.first)
        let files = try await AfrikaansClipCorpus.ensureLocalFiles(for: [clip])
        let url = try #require(files[clip])
        let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size > 10_000)
        let header = try Data(contentsOf: url, options: .mappedIfSafe).prefix(4)
        #expect(header == Data("RIFF".utf8) || header.starts(with: [0xFF, 0xF1]) || size > 100_000)
    }

}

func skipIfNetworkDisabled() throws {
    if AfrikaansClipCorpus.skipNetwork {
        try Test.cancel("Skipping network tests (\(AfrikaansClipCorpus.skipNetworkEnvironmentKey)=1).")
    }
}


