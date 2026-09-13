import SwiftUI

@main
struct FluisterDemoApp: App {
    @State private var transcriber = Transcriber()

    var body: some Scene {
        WindowGroup("Fluister") {
            RootView()
                .environment(transcriber)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 820, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Copy Transcript", action: transcriber.copyTranscript)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
