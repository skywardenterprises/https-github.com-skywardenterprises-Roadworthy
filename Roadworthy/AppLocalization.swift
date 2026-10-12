import Foundation

/// Looks up text in the language chosen in Settings. SwiftUI `Text("…")`
/// literals follow the app's locale on their own; this covers text built as
/// a plain `String` (validation messages, status lines, enum names).
nonisolated enum AppLocalization {
    /// The language picked in Settings, or nil to follow the device.
    static var chosenLanguage: String? {
        let raw = UserDefaults.standard.string(forKey: SettingKey.appLanguage) ?? "system"
        return raw == "system" ? nil : raw
    }

    static var bundle: Bundle {
        guard let code = chosenLanguage,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    static var locale: Locale {
        chosenLanguage.map { Locale(identifier: $0) } ?? .autoupdatingCurrent
    }

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Localized `String`, optionally filled in with `%@` / `%lld` arguments.
nonisolated func L(_ key: String, _ args: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    guard !args.isEmpty else { return format }
    return String(format: format, locale: AppLocalization.locale, arguments: args)
}
