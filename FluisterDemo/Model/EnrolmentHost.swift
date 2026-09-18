import Foundation

struct EnrolledSpeaker: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isNamed: Bool
    var colorIndex: Int
    var embedding: [Float]
}

/// Narrow host: match voice prints and hand out "Speaker N" labels.
/// Speakers only get a real name through the "This is me…" sheet;
/// Fluister never interrupts the conversation to ask.
@MainActor
@Observable
final class EnrolmentHost {
    private(set) var speakers: [EnrolledSpeaker] = []

    struct Assignment: Equatable {
        var speakerID: UUID
        var name: String
        var colorIndex: Int
    }

    func resetSession() {
        speakers = []
    }

    func assign(audio: [Float]) -> Assignment? {
        guard let print = VoicePrint.embedding(from: audio) else { return nil }
        if let match = bestMatch(print) {
            blend(match.id, with: print)
            return Assignment(speakerID: match.id, name: match.name, colorIndex: match.colorIndex)
        }
        let speaker = addAnonymous(embedding: print)
        return Assignment(speakerID: speaker.id, name: speaker.name, colorIndex: speaker.colorIndex)
    }

    func nameLastUnknown(_ name: String, audio: [Float]) -> Assignment? {
        let trimmed = NameParser.displayName(from: name) ?? {
            let folded = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return folded.isEmpty ? nil : folded
        }()
        guard let trimmed, !trimmed.isEmpty else { return nil }
        if let print = VoicePrint.embedding(from: audio), let match = bestMatch(print) {
            return rename(match.id, to: trimmed, embedding: print).map {
                Assignment(speakerID: $0.id, name: $0.name, colorIndex: $0.colorIndex)
            }
        }
        if let unnamed = speakers.last(where: { !$0.isNamed }) {
            return rename(unnamed.id, to: trimmed, embedding: unnamed.embedding).map {
                Assignment(speakerID: $0.id, name: $0.name, colorIndex: $0.colorIndex)
            }
        }
        if let print = VoicePrint.embedding(from: audio) {
            let speaker = add(name: trimmed, embedding: print, named: true)
            return Assignment(speakerID: speaker.id, name: speaker.name, colorIndex: speaker.colorIndex)
        }
        return nil
    }

    func speaker(id: UUID) -> EnrolledSpeaker? {
        speakers.first { $0.id == id }
    }

    private func bestMatch(_ print: [Float]) -> EnrolledSpeaker? {
        var best: (EnrolledSpeaker, Float)?
        for speaker in speakers {
            let score = VoicePrint.cosine(print, speaker.embedding)
            if score >= VoicePrint.matchThreshold, score > (best?.1 ?? -1) {
                best = (speaker, score)
            }
        }
        return best?.0
    }

    private func addAnonymous(embedding: [Float]) -> EnrolledSpeaker {
        let index = speakers.count + 1
        return add(name: "Speaker \(index)", embedding: embedding, named: false)
    }

    private func add(name: String, embedding: [Float], named: Bool) -> EnrolledSpeaker {
        let speaker = EnrolledSpeaker(
            id: UUID(),
            name: name,
            isNamed: named,
            colorIndex: speakers.count,
            embedding: embedding
        )
        speakers.append(speaker)
        return speaker
    }

    @discardableResult
    private func rename(_ id: UUID, to name: String, embedding: [Float]) -> EnrolledSpeaker? {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return nil }
        speakers[index].name = name
        speakers[index].isNamed = true
        speakers[index].embedding = VoicePrint.average(speakers[index].embedding, embedding)
        return speakers[index]
    }

    private func blend(_ id: UUID, with embedding: [Float]) {
        guard let index = speakers.firstIndex(where: { $0.id == id }) else { return }
        speakers[index].embedding = VoicePrint.average(speakers[index].embedding, embedding)
    }
}
