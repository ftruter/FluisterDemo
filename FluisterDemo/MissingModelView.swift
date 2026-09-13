import SwiftUI

struct MissingModelView: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        ContentUnavailableView {
            Label("No Fluister model", systemImage: "waveform")
        } description: {
            Text("This app loads a local WhisperKit Core ML folder. Convert Fluister-turbo with whisperkittools, then choose the folder that contains MelSpectrogram, AudioEncoder, and TextDecoder.")
        } actions: {
            Button("Choose model…", action: transcriber.chooseModel)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
