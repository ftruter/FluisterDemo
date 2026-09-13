import AppKit
import Foundation
@preconcurrency import WhisperKit

struct Caption: Identifiable, Equatable {
    let id: UInt64
    let text: String
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

    private(set) var phase: TranscriberPhase = .missingModel
    private(set) var captions: [Caption] = []
    private(set) var partial: String = ""
    private(set) var inputLevel: Float = 0
    private(set) var modelURL: URL?
    private(set) var modelDisplayName: String = ""

    var isListening: Bool { phase == .listening }
    var canStartListening: Bool { phase == .ready }

    private var kit: WhisperKit?
    private var preparedModelURL: URL?
    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var prepareGeneration = 0
    private var lastConfirmedCount = 0
    private var nextCaptionID: UInt64 = 1
    private var lastLevelPublish = Date.distantPast
    private var scopedURL: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let url = discoverModel() {
            modelURL = url
            modelDisplayName = url.lastPathComponent
            phase = .preparing
        } else {
            phase = .missingModel
        }
    }

    func prepareIfNeeded() {
        guard phase != .listening else { return }
        if kit != nil, preparedModelURL == modelURL, phase == .ready { return }
        startPrepare()
    }

    func retryPrepare() {
        startPrepare()
    }

    func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(
            localized: "Choose the Fluister-turbo Core ML folder (MelSpectrogram, AudioEncoder, TextDecoder).",
            comment: "Open panel prompt for the WhisperKit model folder."
        )
        panel.prompt = String(localized: "Choose", comment: "Open panel confirm button.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard ModelFolder.isComplete(at: url) else {
            phase = .failed(
                String(
                    localized: "That folder is not a WhisperKit Fluister model. It needs MelSpectrogram.mlmodelc, AudioEncoder.mlmodelc, TextDecoder.mlmodelc, tokenizer.json, and config.json.",
                    comment: "Error when the chosen folder is missing required Core ML files."
                )
            )
            return
        }
        try? ModelBookmark.save(url, defaults: defaults)
        beginAccess(url)
        modelURL = url
        modelDisplayName = url.lastPathComponent
        kit = nil
        preparedModelURL = nil
        startPrepare()
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
        nextCaptionID = 1
    }

    func copyTranscript() {
        var lines = captions.map(\.text)
        let live = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty { lines.append(live) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func start() async {
        guard phase == .ready, let kit, let tokenizer = kit.tokenizer else { return }
        await stopStreaming()
        lastConfirmedCount = 0
        inputLevel = 0
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language.whisperCode,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: false
        )
        // WhisperKit's pipeline types are not Sendable yet; the stream actor
        // takes exclusive ownership of these objects for the session.
        nonisolated(unsafe) let audioEncoder = kit.audioEncoder
        nonisolated(unsafe) let featureExtractor = kit.featureExtractor
        nonisolated(unsafe) let segmentSeeker = kit.segmentSeeker
        nonisolated(unsafe) let textDecoder = kit.textDecoder
        nonisolated(unsafe) let audioProcessor = kit.audioProcessor
        nonisolated(unsafe) let ownedTokenizer = tokenizer
        let streamer = AudioStreamTranscriber(
            audioEncoder: audioEncoder,
            featureExtractor: featureExtractor,
            segmentSeeker: segmentSeeker,
            textDecoder: textDecoder,
            tokenizer: ownedTokenizer,
            audioProcessor: audioProcessor,
            decodingOptions: options,
            stateChangeCallback: { @Sendable [weak self] _, newState in
                let confirmed = newState.confirmedSegments.map(\.text)
                let current = newState.currentText
                let energy = Array(newState.bufferEnergy.suffix(8))
                Task { @MainActor in
                    self?.handle(confirmedTexts: confirmed, currentText: current, energy: energy)
                }
            }
        )
        self.streamer = streamer
        phase = .listening
        streamTask = Task { [weak self] in
            do {
                try await streamer.startStreamTranscription()
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error.localizedDescription, keepKit: true)
            }
        }
    }

    func stop() async {
        await stopStreaming()
        if phase == .listening {
            phase = kit != nil ? .ready : (modelURL == nil ? .missingModel : .preparing)
        }
    }

    private func restart() async {
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
            fail(error.localizedDescription, keepKit: false)
        }
    }

    private func stopStreaming() async {
        streamTask?.cancel()
        streamTask = nil
        await streamer?.stopStreamTranscription()
        streamer = nil
        lastConfirmedCount = 0
        inputLevel = 0
        partial = ""
    }

    private func handle(confirmedTexts: [String], currentText: String, energy: [Float]) {
        if confirmedTexts.count > lastConfirmedCount {
            let newly = confirmedTexts.suffix(from: lastConfirmedCount)
            lastConfirmedCount = confirmedTexts.count
            for raw in newly {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                captions.append(Caption(id: nextCaptionID, text: text))
                nextCaptionID += 1
            }
            if captions.count > 400 {
                captions.removeFirst(captions.count - 400)
            }
        }
        let confirmed = confirmedTexts.joined()
        let nextPartial = currentText == confirmed ? "" : currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if nextPartial != partial {
            partial = nextPartial
        }
        publishLevel(energy)
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
        streamTask?.cancel()
        streamTask = nil
        streamer = nil
        if !keepKit {
            kit = nil
            preparedModelURL = nil
        }
        inputLevel = 0
        phase = .failed(message)
    }

    private func discoverModel() -> URL? {
        if let bookmarked = ModelBookmark.resolve(defaults: defaults) {
            beginAccess(bookmarked)
            if ModelFolder.isComplete(at: bookmarked) {
                return bookmarked
            }
        }
        if let env = ProcessInfo.processInfo.environment["FLUISTER_MODEL_FOLDER"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if ModelFolder.isComplete(at: url) { return url }
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundledID = Bundle.main.bundleIdentifier ?? "truter.com.fluister.demo"
        let supportModel = support
            .appendingPathComponent(bundledID, isDirectory: true)
            .appendingPathComponent("fluister-turbo-v2", isDirectory: true)
        if ModelFolder.isComplete(at: supportModel) { return supportModel }

        if let resource = Bundle.main.resourceURL?
            .appendingPathComponent("fluister-turbo-v2", isDirectory: true),
           ModelFolder.isComplete(at: resource)
        {
            return resource
        }

        #if DEBUG
        if let nearby = nearbyConversionOutput(), ModelFolder.isComplete(at: nearby) {
            return nearby
        }
        #endif
        return nil
    }

    private func beginAccess(_ url: URL) {
        if scopedURL?.path != url.path {
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = url
        }
        _ = url.startAccessingSecurityScopedResource()
    }

    #if DEBUG
    private func nearbyConversionOutput(filePath: String = #filePath) -> URL? {
        var url = URL(fileURLWithPath: filePath)
        url.deleteLastPathComponent()
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("FluisterTV/Tools/convert/out/fluister-turbo-v2", isDirectory: true)
            if ModelFolder.isComplete(at: candidate) { return candidate }
        }
        return nil
    }
    #endif
}

enum TranscriberError: LocalizedError {
    case missingTokenizer
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .missingTokenizer:
            String(localized: "The Fluister model is missing a tokenizer.", comment: "Error when tokenizer.json cannot be loaded.")
        case .microphoneDenied:
            String(localized: "Microphone access was not granted.", comment: "Error when the user denies the microphone prompt.")
        }
    }
}
