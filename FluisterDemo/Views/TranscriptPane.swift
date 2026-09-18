import SwiftUI

struct TranscriptPane: View {
    @Environment(Transcriber.self) private var transcriber

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcriber.captions) { caption in
                        CaptionRow(
                            text: caption.text,
                            speakerName: caption.speakerName,
                            color: .speaker(for: caption.colorIndex, of: transcriber.captions.count),
                            isPartial: false
                        )
                        .id(caption.id)
                    }
                    if !transcriber.partial.isEmpty {
                        CaptionRow(
                            text: transcriber.partial,
                            speakerName: nil,
                            color: .secondary,
                            isPartial: true
                        )
                        .id("partial")
                    }
                }
                .padding(16)
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
    let speakerName: String?
    let color: Color
    let isPartial: Bool
    /// Live partials rewrite the sentence as they go; wrapping then unwrapping
    /// would bounce the whole transcript. Grow-only height stops that.
    @State private var floorHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let speakerName, !speakerName.isEmpty {
                Text(speakerName)
                    .font(.headline)
                    .foregroundStyle(color)
            }
            Text(text)
                .font(.title)
                .foregroundStyle(isPartial ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .background {
            if isPartial {
                GeometryReader { geo in
                    Color.clear.preference(key: CaptionHeightKey.self, value: geo.size.height)
                }
            }
        }
        .onPreferenceChange(CaptionHeightKey.self) { height in
            guard isPartial, height > floorHeight + 0.5 else { return }
            floorHeight = height
        }
        .frame(maxWidth: .infinity, minHeight: isPartial ? floorHeight : 0, alignment: .topLeading)
        .padding(12)
        .background(color.opacity(isPartial ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityAddTraits(isPartial ? .updatesFrequently : [])
        .accessibilityLabel(speakerName.map { "\($0): \(text)" } ?? text)
    }
}

private struct CaptionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}



#Preview {
    CaptionRow(text: "Hoe gaan dit?", speakerName: "Fred", color: .speaker(for: 0), isPartial: false)
}
