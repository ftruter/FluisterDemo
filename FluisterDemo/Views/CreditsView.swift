import SwiftUI
import UIKit

struct OpenSourceCredit: Identifiable {
    let id: String
    let name: LocalizedStringResource
    let summary: LocalizedStringResource
    let links: [URL]
}

extension OpenSourceCredit {
    static let all: [OpenSourceCredit] = [
        OpenSourceCredit(
            id: "digiphyte",
            name: "DigiPhyte — Fluister-turbo",
            summary: "South African Whisper for Afrikaans, SA English, and everyday code-switching. MIT.",
            links: [
                URL(string: "https://huggingface.co/digiphyte/fluister-turbo")!,
                URL(string: "https://huggingface.co/digiphyte/fluister-turbo-transformers")!,
                URL(string: "https://huggingface.co/FTruter/fluister-turbo-coreml")!,
            ]
        ),
        OpenSourceCredit(
            id: "openai",
            name: "OpenAI — Whisper large-v3-turbo",
            summary: "Base speech-recognition model. Apache 2.0.",
            links: [
                URL(string: "https://huggingface.co/openai/whisper-large-v3-turbo")!,
            ]
        ),
        OpenSourceCredit(
            id: "argmax",
            name: "Argmax — WhisperKit",
            summary: "On-device Core ML inference and the converter used for this Metal build. MIT.",
            links: [
                URL(string: "https://github.com/argmaxinc/WhisperKit")!,
                URL(string: "https://github.com/argmaxinc/whisperkittools")!,
            ]
        ),
        OpenSourceCredit(
            id: "training",
            name: "Training data",
            summary: "andreoosthuizen/afrikaans-30s (CC BY 4.0) and the NCHLT Afrikaans and English speech corpora (CC BY 3.0).",
            links: [
                URL(string: "https://huggingface.co/datasets/andreoosthuizen/afrikaans-30s")!,
                URL(string: "https://huggingface.co/datasets/danielshaps/nchlt_speech_afr")!,
                URL(string: "https://huggingface.co/datasets/danielshaps/nchlt_speech_eng")!,
            ]
        ),
    ]
}

struct CreditsView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                CreditsIntro()
                ForEach(OpenSourceCredit.all) { credit in
                    CreditRow(name: credit.name, summary: credit.summary, links: credit.links)
                }
            }
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            UIApplication.shared.open(url)
            return .handled
        })
    }
}

struct CreditsIntro: View {
    var body: some View {
        Text("This demo is built with these open-source models and tools. Each link opens in Safari.", comment: "Intro on the Credits page. Links leave the app and open in Safari.")
            .font(.body)
            .foregroundStyle(.secondary)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

struct CreditRow: View {
    let name: LocalizedStringResource
    let summary: LocalizedStringResource
    let links: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(links, id: \.self) { url in
                CreditLink(url: url)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct CreditLink: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            Label(url.absoluteString, systemImage: "safari")
                .font(.footnote)
                .multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Open in Safari")
        .accessibilityValue(url.absoluteString)
    }
}

#Preview {
    CreditsView(isPresented: .constant(true))
}
