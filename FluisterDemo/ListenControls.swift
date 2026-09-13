import SwiftUI

struct ListenControls: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        @Bindable var transcriber = transcriber
        HStack(spacing: 16) {
            Button(action: transcriber.toggle) {
                Label(
                    transcriber.isListening
                        ? "Stop listening"
                        : "Listen",
                    systemImage: transcriber.isListening ? "stop.fill" : "mic.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(transcriber.isListening ? .red : .accentColor)
            .controlSize(.large)
            .disabled(!transcriber.isListening && !transcriber.canStartListening)

            LevelMeter(level: transcriber.inputLevel)
                .frame(width: 88, height: 12)
                .accessibilityLabel("Microphone level")
                .accessibilityValue("\(Int((transcriber.inputLevel * 100).rounded())) percent")

            Picker("Language", selection: $transcriber.language) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .accessibilityHint("Chooses Afrikaans or English for on-device speech recognition. Autodetect is off so Afrikaans is not treated as Dutch.")

            Spacer(minLength: 8)

            Button("Choose model…", action: transcriber.chooseModel)
            Button("Copy", action: transcriber.copyTranscript)
                .disabled(transcriber.captions.isEmpty && transcriber.partial.isEmpty)
            Button("Clear", action: transcriber.clearTranscript)
                .disabled(transcriber.captions.isEmpty && transcriber.partial.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
