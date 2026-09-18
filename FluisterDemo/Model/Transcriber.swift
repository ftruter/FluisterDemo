import Foundation
import os
import UIKit
@preconcurrency import WhisperKit

struct Caption: Identifiable, Equatable {
    let id: UInt64
    var text: String
    var speakerID: UUID?
    var speakerName: String?
    var colorIndex: Int
}

enum TranscriberPhase: Equatable {
    case missingModel
    case preparing
    case ready
    case listening
    case failed(String)
}

@MainActor
@Observable
final class Transcriber {
    var language: TranscriptionLanguage = .afrikaans {
        didSet {
            guard language != oldValue, phase == .listening else { return }
            Task { await restart() }
        }
    }

    private(set) var phase: TranscriberPhase = .missingModel {
        didSet {
            // Keep the screen awake during long listening sessions.
            UIApplication.shared.isIdleTimerDisabled = phase == .listening
        }
    }
    private(set) var captions: [Caption] = []
    private(set) var partial: String = ""
    private(set) var waitingForSpeech = false
    private(set) var inputLevel: Float = 0
    private(set) var modelURL: URL?
    private(set) var modelDisplayName: String = ""
    let enrolment = EnrolmentHost()
    let models: ModelStore

    var isListening: Bool { phase == .listening }
    var canStartListening: Bool { phase == .ready }

    private var kit: WhisperKit?
    private var preparedModelURL: URL?
    private var streamTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var prepareGeneration = 0
    private var listenGeneration = 0
    private var nextCaptionID: UInt64 = 1
    private var stabiliser = PartialStabiliser()
    private var lastLevelPublish = Date.distantPast
    private var lastCommittedAudio: [Float] = []
    private let log = Logger(subsystem: "truter.com.fluister.demo", category: "Listen")

    init(models: ModelStore = ModelStore()) {
        self.models = models
        if let url = models.usableFolder {
            modelURL = url
            modelDisplayName = "Fluister-turbo"
            phase = .preparing
        } else {
            phase = .missingModel
        }
    }

    func prepareIfNeeded() {
        Task { await bootstrap() }
    }

    func retryPrepare() {
        Task { await bootstrap() }
    }

    func downloadModel() {
        Task { await runDownload() }
    }

    func toggle() {
        Task {
            if isListening {
                await stop()
            } else if canStartListening {
                await start()
            }
        }
    }

    func clearTranscript() {
        captions = []
        partial = ""
        stabiliser.reset()
        nextCaptionID = 1
        lastCommittedAudio = []
        enrolment.resetSession()
    }

    func copyTranscript() {
        var lines = captions.map { caption in
            if let name = caption.speakerName, !name.isEmpty {
                return "\(name): \(caption.text)"
            }
            return caption.text
        }
        let live = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { lines.append(live) }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    func nameLastSpeaker(_ name: String) {
        guard let assignment = enrolment.nameLastUnknown(name, audio: lastCommittedAudio) else { return }
        relabel(assignment)
    }

    func start() async {
        guard phase == .ready, let kit, kit.tokenizer != nil else { return }
        await stopStreaming()
        inputLevel = 0
        waitingForSpeech = true
        do {
            // No live callback: this app defaults to MainActor isolation, and
            // WhisperKit invokes the tap on the Core Audio realtime thread.
            // Passing a closure here traps in _swift_task_checkIsolatedSwift.
            // Levels are published from listenLoop instead.
            //
            // WhisperKit still calls AVAudioSession.setActive synchronously.
            // iOS 27 warns if that happens on the main thread; hop off it.
            nonisolated(unsafe) let processor = kit.audioProcessor
            try await Task.detached(priority: .userInitiated) {
                try processor.startRecordingLive(callback: nil)
            }.value
        } catch {
            fail(failureMessage(for: error), keepKit: true)
            return
        }
        listenGeneration += 1
        let generation = listenGeneration
        let languageCode = language.whisperCode
        // WhisperKit's pipeline types are not Sendable; this task owns them
        // exclusively for the listen session, off the main actor so the UI
        // stays responsive while a short slice decodes.
        nonisolated(unsafe) let ownedKit = kit
        phase = .listening
        log.notice("live listen started (\(languageCode, privacy: .public))")
        streamTask = Task.detached { [weak self] in
            await Self.listenLoop(kit: ownedKit, languageCode: languageCode, generation: generation, transcriber: self)
        }
    }

    func stop() async {
        await commitPartial()
        await stopStreaming()
        if models.pendingPromote {
            kit = nil
            preparedModelURL = nil
            if let url = try? models.promoteStaging() {
                modelURL = url
                modelDisplayName = "Fluister-turbo"
                startPrepare()
                return
            }
        }
        if phase == .listening {
            phase = kit != nil ? .ready : (modelURL == nil ? .missingModel : .preparing)
        }
    }

    private func restart() async {
        await commitPartial()
        await stopStreaming()
        await start()
    }

    private func startPrepare() {
        prepareTask?.cancel()
        prepareGeneration += 1
        let generation = prepareGeneration
        guard let modelURL else {
            kit = nil
            preparedModelURL = nil
            phase = .missingModel
            return
        }
        phase = .preparing
        prepareTask = Task { await prepareModel(at: modelURL, generation: generation) }
    }

    private func prepareModel(at url: URL, generation: Int) async {
        await stopStreaming()
        kit = nil
        preparedModelURL = nil
        do {
            let granted = await AudioProcessor.requestRecordPermission()
            guard generation == prepareGeneration else { return }
            guard granted else { throw TranscriberError.microphoneDenied }

            let config = WhisperKitConfig(
                modelFolder: url.path,
                prewarm: false,
                download: false
            )
            let kit = try await WhisperKit(config)
            guard generation == prepareGeneration else { return }
            guard kit.tokenizer != nil else { throw TranscriberError.missingTokenizer }

            self.kit = kit
            preparedModelURL = url
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            guard generation == prepareGeneration else { return }
            fail(failureMessage(for: error), keepKit: false)
        }
    }

    /// Resolves an error message in the picked UI language rather than the system language.
    private func failureMessage(for error: Error) -> String {
        if let error = error as? TranscriberError {
            return error.message(bundle: language.bundle)
        }
        return error.localizedDescription
    }

    private func stopStreaming() async {
        listenGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        kit?.audioProcessor.stopRecording()
        waitingForSpeech = false
        inputLevel = 0
        partial = ""
        stabiliser.reset()
    }

    func shouldContinueListening(_ generation: Int) -> Bool {
        phase == .listening && listenGeneration == generation
    }

    func setWaitingForSpeech(_ waiting: Bool) {
        guard phase == .listening, waitingForSpeech != waiting else { return }
        waitingForSpeech = waiting
    }

    func setPartial(_ text: String, isFinal: Bool = false) {
        guard phase == .listening else { return }
        let visible = LiveListen.visibleText(text)
        guard !visible.isEmpty else { return }
        let display = isFinal ? stabiliser.updateFinal(visible) : stabiliser.updateLive(visible)
        guard display != partial else { return }
        partial = display
        if !display.isEmpty {
            waitingForSpeech = false
        }
    }

    /// Commits whatever the streaming decodes last showed. Used when a session
    /// ends mid-utterance; silence commits go through `commitFinal` instead.
    func commitPartial(audio: [Float] = []) async {
        let text = LiveListen.visibleText(partial)
        partial = ""
        stabiliser.reset()
        guard !text.isEmpty else { return }
        appendCaption(text, audio: audio)
    }

    /// Commits the text of the dedicated end-of-utterance decode. The generation
    /// check drops results that finish after the session stopped or restarted,
    /// which would otherwise duplicate the caption `stop()` already committed.
    func commitFinal(_ text: String, audio: [Float], generation: Int) {
        guard listenGeneration == generation else { return }
        partial = ""
        stabiliser.reset()
        let visible = LiveListen.visibleText(text)
        guard !visible.isEmpty else { return }
        appendCaption(visible, audio: audio)
    }

    /// Drops an utterance that had too little voiced audio to be speech.
    func discardPartial() {
        partial = ""
        stabiliser.reset()
    }

    private func appendCaption(_ text: String, audio: [Float]) {
        lastCommittedAudio = audio
        var caption = Caption(id: nextCaptionID, text: text, speakerID: nil, speakerName: nil, colorIndex: 0)
        nextCaptionID += 1
        let assignment = enrolment.assign(audio: audio)
        if let assignment {
            caption.speakerID = assignment.speakerID
            caption.speakerName = assignment.name
            caption.colorIndex = assignment.colorIndex
            relabel(assignment)
        }
        captions.append(caption)
        log.info("commit \(caption.speakerName ?? "?", privacy: .public): \(text, privacy: .public)")
        if captions.count > 400 {
            captions.removeFirst(captions.count - 400)
        }
    }

    private func relabel(_ assignment: EnrolmentHost.Assignment) {
        for index in captions.indices where captions[index].speakerID == assignment.speakerID {
            captions[index].speakerName = assignment.name
            captions[index].colorIndex = assignment.colorIndex
        }
    }

    func failLive(_ error: Error) {
        fail(failureMessage(for: error), keepKit: true)
    }

    private nonisolated static func listenLoop(
        kit: WhisperKit,
        languageCode: String,
        generation: Int,
        transcriber: Transcriber?
    ) async {
        var cursor = 0
        var segmenter = LiveListenSegmenter()
        var everHeardVoice = false
        let trailingFrames = LiveListen.trailingSilenceFrames
        let options = LiveListen.decodingOptions(language: languageCode)
        let finalOptions = LiveListen.finalDecodingOptions(language: languageCode)

        while !Task.isCancelled {
            guard await transcriber?.shouldContinueListening(generation) == true else { return }

            let samples = Array(kit.audioProcessor.audioSamples)
            let energy = kit.audioProcessor.relativeEnergy
            await transcriber?.publishLevel(Array(energy.suffix(8)))

            let voice = LiveListen.isVoice(in: energy.suffix(trailingFrames))
            if voice {
                everHeardVoice = true
                await transcriber?.setWaitingForSpeech(false)
            }

            if let commit = segmenter.step(sampleCount: samples.count, energy: energy) {
                cursor = segmenter.committedSamples
                if commit.voiced, !commit.utterance.isEmpty {
                    let utterance = Array(samples[commit.utterance])
                    do {
                        let results: [TranscriptionResult] = try await kit.transcribe(
                            audioArray: utterance,
                            decodeOptions: finalOptions
                        )
                        let text = LiveListen.visibleText(results.map(\.text).joined(separator: " "))
                        await transcriber?.commitFinal(text, audio: utterance, generation: generation)
                    } catch is CancellationError {
                        return
                    } catch {
                        await transcriber?.failLive(error)
                        return
                    }
                } else {
                    await transcriber?.discardPartial()
                }
                try? await Task.sleep(nanoseconds: LiveListen.pollNanoseconds)
                continue
            }

            let newSamples = samples.count - cursor
            if newSamples < LiveListen.minNewSamples {
                if !everHeardVoice {
                    await transcriber?.setWaitingForSpeech(true)
                }
                try? await Task.sleep(nanoseconds: LiveListen.pollNanoseconds)
                continue
            }

            let trailing = energy.suffix(trailingFrames)
            let trailingSilent = trailing.count >= trailingFrames && !LiveListen.isVoice(in: trailing)
            if !voice, trailingSilent, await transcriber?.partial.isEmpty == true {
                cursor = samples.count
                try? await Task.sleep(nanoseconds: LiveListen.pollNanoseconds)
                continue
            }

            cursor = samples.count
            let start = max(0, segmenter.committedSamples - LiveListen.overlapSamples)
            guard samples.count > start else { continue }
            let slice = Array(samples[start..<samples.count])

            do {
                let results: [TranscriptionResult] = try await kit.transcribe(
                    audioArray: slice,
                    decodeOptions: options,
                    callback: { progress in
                        let text = LiveListen.visibleText(progress.text)
                        if !text.isEmpty {
                            Task { await transcriber?.setPartial(text) }
                        }
                        return nil
                    }
                )
                let text = LiveListen.visibleText(results.map(\.text).joined(separator: " "))
                if !text.isEmpty {
                    await transcriber?.setPartial(text, isFinal: true)
                }
            } catch is CancellationError {
                return
            } catch {
                await transcriber?.failLive(error)
                return
            }
        }
    }

    private func publishLevel(_ energy: [Float]) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelPublish) > 0.08 else { return }
        lastLevelPublish = now
        let peak = energy.suffix(8).max() ?? 0
        let scaled = min(1, max(0, peak))
        if abs(scaled - inputLevel) > 0.02 {
            inputLevel = scaled
        } else if scaled == 0, inputLevel != 0 {
            inputLevel = 0
        }
    }

    private func fail(_ message: String, keepKit: Bool) {
        listenGeneration += 1
        streamTask?.cancel()
        streamTask = nil
        kit?.audioProcessor.stopRecording()
        waitingForSpeech = false
        if !keepKit {
            kit = nil
            preparedModelURL = nil
        }
        inputLevel = 0
        partial = ""
        stabiliser.reset()
        phase = .failed(message)
    }

    private func bootstrap() async {
        await models.refreshFromHub()
        if models.hasIncompleteDownload {
            if models.hasLocal {
                Task { await runDownload() }
            } else {
                await runDownload()
                return
            }
        }
        if phase != .listening, let url = try? models.applyStagingIfIdle(isListening: false) {
            modelURL = url
            modelDisplayName = "Fluister-turbo"
            kit = nil
            preparedModelURL = nil
        }
        guard let folder = models.usableFolder else {
            if phase != .listening {
                modelURL = nil
                kit = nil
                preparedModelURL = nil
                phase = .missingModel
            }
            return
        }
        modelURL = folder
        modelDisplayName = "Fluister-turbo"
        if phase == .listening { return }
        if kit != nil, preparedModelURL == folder, phase == .ready { return }
        startPrepare()
    }

    private func runDownload() async {
        do {
            try await models.downloadToStaging()
            if phase == .listening, models.pendingPromote {
                return
            }
            let url = try models.promoteStaging()
            modelURL = url
            modelDisplayName = "Fluister-turbo"
            startPrepare()
        } catch {
            if models.hasLocal { return }
            phase = .missingModel
        }
    }
}

enum TranscriberError: LocalizedError {
    case missingTokenizer
    case microphoneDenied

    var errorDescription: String? { message(bundle: .main) }

    func message(bundle: Bundle) -> String {
        switch self {
        case .missingTokenizer:
            String(localized: "The Fluister model is missing a tokenizer.", bundle: bundle, comment: "Error when tokenizer.json cannot be loaded.")
        case .microphoneDenied:
            String(localized: "Microphone access was not granted.", bundle: bundle, comment: "Error when the user denies the microphone prompt.")
        }
    }
}
