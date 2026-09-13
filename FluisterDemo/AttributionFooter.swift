import SwiftUI

struct AttributionFooter: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Model by DigiPhyte. Inference with WhisperKit on Core ML. No cloud.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Afrikaans · SA English")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }
}
