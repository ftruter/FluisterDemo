import SwiftUI

struct TranscriptPane: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcriber.captions) { caption in
                        CaptionRow(text: caption.text, isPartial: false)
                            .id(caption.id)
                    }
                    if !transcriber.partial.isEmpty {
                        CaptionRow(text: transcriber.partial, isPartial: true)
                            .id("partial")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcriber.captions.count) {
                scrollToEnd(proxy)
            }
            .onChange(of: transcriber.partial) {
                scrollToEnd(proxy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcript")
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if !transcriber.partial.isEmpty {
            proxy.scrollTo("partial", anchor: .bottom)
        } else if let last = transcriber.captions.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

struct CaptionRow: View {
    let text: String
    let isPartial: Bool

    var body: some View {
        Text(text)
            .font(.title2)
            .foregroundStyle(isPartial ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(isPartial ? .updatesFrequently : [])
    }
}
