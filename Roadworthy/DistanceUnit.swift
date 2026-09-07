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

private let milesPerKilometer = 0.621371
private let kilometersPerMile = 1.60934

/// Converts a value already stored in miles into the person's preferred
/// unit, for display.
nonisolated func convertFromMiles(_ miles: Int, to unit: DistanceUnit) -> Int {
    switch unit {
    case .miles:
        return miles
    case .kilometers:
        return Int((Double(miles) * kilometersPerMile).rounded())
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
        return Int((Double(value) * milesPerKilometer).rounded())
    }
}

/// A ready-to-display string like "42,310 mi" or "68,098 km".
nonisolated func formattedDistance(_ miles: Int, unit: DistanceUnit) -> String {
    "\(convertFromMiles(miles, to: unit).formatted()) \(unit.rawValue)"
}
