import Foundation

/// The person's preferred distance unit, stored as a simple app-wide
/// preference (not per-vehicle) via @AppStorage. All distances are still
/// stored internally in miles everywhere in the data model — this only
/// affects how they're displayed and entered.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles = "mi"
    case kilometers = "km"

    var id: String { rawValue }

    var displayName: String {
        self == .miles ? "Miles" : "Kilometers"
    }
}

/// Exact by definition. Both conversions use this one constant so that
/// converting miles to km for display and back to miles on save always
/// returns the original value. The previous pair of rounded constants
/// (1.60934 and 0.621371) weren't exact inverses, so readings from about
/// 68,000 miles up shifted by a mile each time a record was opened and
/// saved in kilometer mode.
nonisolated private let kilometersPerMile = 1.609344

/// Converts a value already stored in miles into the person's preferred
/// unit, for display.
nonisolated func convertFromMiles(_ miles: Int, to unit: DistanceUnit) -> Int {
    switch unit {
    case .miles:
        return miles
    case .kilometers:
        // Int(exactly:) returns nil instead of crashing for an absurd stored
        // value (such as a 19-digit odometer saved before input was capped).
        return Int(exactly: (Double(miles) * kilometersPerMile).rounded()) ?? 0
    }
}

/// Converts a value the person typed in their preferred unit back into
/// miles, for storage — since every distance in the data model is kept
/// internally in miles regardless of display preference.
nonisolated func convertToMiles(_ value: Int, from unit: DistanceUnit) -> Int {
    switch unit {
    case .miles:
        return value
    case .kilometers:
        return Int(exactly: (Double(value) / kilometersPerMile).rounded()) ?? 0
    }
}

/// A ready-to-display string like "42,310 mi" or "68,098 km".
nonisolated func formattedDistance(_ miles: Int, unit: DistanceUnit) -> String {
    "\(convertFromMiles(miles, to: unit).formatted()) \(unit.rawValue)"
}
