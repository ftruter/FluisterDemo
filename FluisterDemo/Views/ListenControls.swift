import SwiftUI

struct ListenBar: View {
    @Environment(Transcriber.self) private var transcriber
    @State private var askingName = false
    @State private var showingCredits = false

    var body: some View {
        @Bindable var transcriber = transcriber
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                StartListeningButton()
                if transcriber.isListening {
                    LevelMeter(level: transcriber.inputLevel)
                        .frame(width: 64, height: 8)
                }
                LanguagePicker()
                Spacer(minLength: 8)
                SessionMenu(askingName: $askingName, showingCredits: $showingCredits)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    StartListeningButton()
                    if transcriber.isListening {
                        LevelMeter(level: transcriber.inputLevel)
                            .frame(height: 8)
                    }
                }
                HStack {
                    LanguagePicker()
                    Spacer(minLength: 8)
                    SessionMenu(askingName: $askingName, showingCredits: $showingCredits)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .sheet(isPresented: $askingName) {
            NameSpeakerSheet(isPresented: $askingName) { name in
                transcriber.nameLastSpeaker(name)
            }
        }
        .sheet(isPresented: $showingCredits) {
            CreditsView(isPresented: $showingCredits)
        }
    }
}

struct StartListeningButton: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        Button(action: transcriber.toggle) {
            Label(
                transcriber.isListening ? "Stop listening" : "Start listening",
                systemImage: transcriber.isListening ? "stop.fill" : "mic.fill"
            )
            .font(.headline)
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(transcriber.isListening ? .red : .accentColor)
        .controlSize(.large)
        .disabled(!transcriber.isListening && !transcriber.canStartListening)
        .accessibilityHint("Starts on-device transcription. Apple requires a tap before the microphone turns on.")
    }
}

struct LanguagePicker: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        @Bindable var transcriber = transcriber
        Picker("UI language", selection: $transcriber.language) {
            ForEach(TranscriptionLanguage.allCases) { language in
                Text(language.title).tag(language)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("UI language")
        .accessibilityHint("Chooses Afrikaans or English for captions and on-device speech recognition. Autodetect is off so Afrikaans is not treated as Dutch.")
    }
}

struct SessionMenu: View {
    @Environment(Transcriber.self) private var transcriber
    @Binding var askingName: Bool
    @Binding var showingCredits: Bool

    var body: some View {
        Menu {
            Button("This is me…") { askingName = true }
                .disabled(transcriber.captions.isEmpty)
            Button("Copy") { transcriber.copyTranscript() }
                .disabled(transcriber.captions.isEmpty && transcriber.partial.isEmpty)
            Button("Clear") { transcriber.clearTranscript() }
                .disabled(transcriber.captions.isEmpty && transcriber.partial.isEmpty)
            Button {
                showingCredits = true
            } label: {
                Text("Credits to", comment: "Menu item that opens the open-source credits page.")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("More")
    }
}

struct NameSpeakerSheet: View {
    @Binding var isPresented: Bool
    var onSave: (String) -> Void
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("Name this speaker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        isPresented = false
    }
}

#Preview {
    ListenBar()
        .environment(Transcriber())
}
