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

    /// Locale applied to the SwiftUI environment so the UI follows the picked language.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Localization bundle for `String(localized:)` lookups, which ignore the
    /// SwiftUI environment locale and would otherwise use the system language.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}
