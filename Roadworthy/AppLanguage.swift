import Foundation

/// The person's language preference. ".system" means "follow the iPhone's
/// own language setting" (the default, and the normal iOS behavior) — every
/// other case forces the app into that specific language regardless of what
/// the device itself is set to.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .chineseSimplified: return "中文（简体）"
        case .hindi: return "हिन्दी"
        }
    }

    /// Nil for .system, meaning "don't override — let the app follow the
    /// device's own locale, live-updating if that ever changes."
    var locale: Locale? {
        self == .system ? nil : Locale(identifier: rawValue)
    }
}
