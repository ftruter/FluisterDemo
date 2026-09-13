import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Equatable {
    case afrikaans = "af"
    case english = "en"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .afrikaans: "Afrikaans"
        case .english: "English"
        }
    }

    var whisperCode: String { rawValue }
}
