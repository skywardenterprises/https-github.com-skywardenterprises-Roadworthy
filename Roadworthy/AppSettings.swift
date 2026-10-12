import Foundation

/// `nonisolated` so these constants can be read from any context (the
/// project uses main-actor default isolation).
///
/// Every UserDefaults / @AppStorage key in one place. A typo in a key
/// string silently creates a separate setting, so views refer to these
/// constants instead of typing the strings.
nonisolated enum SettingKey {
    static let distanceUnit = "distanceUnit"
    static let appLanguage = "appLanguage"
    static let businessMileageRate = "businessMileageRate"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let hasSeenImportPrompt = "hasSeenImportPrompt"
    /// Per-vehicle "remind me later" date for the odometer check-in.
    static func odometerSnooze(_ vehicleID: UUID?) -> String {
        "odometerCheckInSnooze.\(vehicleID?.uuidString ?? "none")"
    }
}

/// Default values that more than one screen depends on.
nonisolated enum SettingDefault {
    /// IRS standard mileage rate used until the person sets their own.
    static let businessMileageRate = 0.76
}

/// The currency every amount is shown in. One constant, so supporting
/// another currency later is a single change instead of 25.
nonisolated enum AppCurrency {
    static let code = "USD"
}
