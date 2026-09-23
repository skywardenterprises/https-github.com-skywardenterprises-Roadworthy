import Foundation

// MARK: - Per-vehicle-type sanity range

extension VehicleType {
    /// Realistic MPG range for this kind of vehicle. Anything outside it
    /// almost certainly means something's off in the underlying data: a
    /// mistyped odometer reading, a fill-up misclassified as full/partial,
    /// or a fill-up that was never logged (common with imported data).
    ///
    /// Ranges differ by type because a single universal range either
    /// flags most gas RVs (6-10 MPG is normal) or hides real errors on
    /// small motorcycles and scooters (80+ MPG is normal).
    var plausibleMPGRange: ClosedRange<Double> {
        switch self {
        case .car: return 8...75
        case .truck: return 5...40
        case .rv: return 4...20
        case .motorcycle: return 15...120
        case .other: return 4...120
        }
    }
}

// MARK: - Interval

/// Why an interval was excluded from MPG stats. Every excluded interval
/// carries one, so nothing drops out of the stats without being surfaced.
enum MPGIssue: Equatable {
    /// End odometer is the same as the start (duplicate entry or typo).
    case noDistance
    /// A fill-up in this stretch has zero, negative, or missing gallons.
    case missingFuelAmount
    /// A fill-up dated inside this stretch has no odometer reading, so its
    /// gallons couldn't be placed and the MPG would be inflated.
    case missingOdometerInStretch
    /// Outside the realistic range for this vehicle type.
    case outsideRangeForVehicleType(ClosedRange<Double>)
    /// Within the type range, but far from this vehicle's own median.
    case unusualForThisVehicle(median: Double)
}

/// One "full tank to full tank" stretch, with the MPG calculated for it.
struct MPGInterval: Identifiable {
    let id = UUID()
    let startLog: FuelLog
    let endLog: FuelLog
    let milesDriven: Int
    let gallonsUsed: Double
    /// 0 when it can't be calculated (no distance or no fuel). Check `issue`.
    let mpg: Double
    var issue: MPGIssue?

    var isPlausible: Bool { issue == nil }

    /// Plain-language explanation for the Data Quality list.
    var issueDescription: String? {
        guard let issue else { return nil }
        switch issue {
        case .noDistance:
            return "The odometer didn't advance between these two full fill-ups. This is likely a duplicate entry or a mileage typo."
        case .missingFuelAmount:
            return "A fill-up in this stretch has no gallons recorded."
        case .missingOdometerInStretch:
            return "A fill-up in this stretch has no odometer reading, so its gallons couldn't be counted."
        case .outsideRangeForVehicleType(let range):
            return "Outside the realistic range for this vehicle type (\(Int(range.lowerBound))–\(Int(range.upperBound)) MPG). Check for a mistyped odometer, a missed fill-up, or a full/partial mix-up."
        case .unusualForThisVehicle(let median):
            return "Far from this vehicle's typical \(median.formatted(.number.precision(.fractionLength(1)))) MPG."
        }
    }
}

// MARK: - Calculator

enum MPGCalculator {
    /// Every full-tank-to-full-tank interval found in the given fuel logs,
    /// plausible or not. Gallons used includes every fill-up in the stretch
    /// (partials included), not just the ending full-tank fill-up.
    ///
    /// - Logs with no odometer reading (mileage <= 0) are left out of the
    ///   chain, and any interval they fall inside (by date) is flagged.
    /// - Logs are ordered by mileage, then date, so entries at the same
    ///   odometer reading always land in the same order.
    /// - Intervals that can't be calculated are returned with an issue
    ///   rather than dropped.
    static func intervals(for fuelLogs: [FuelLog], vehicleType: VehicleType? = nil) -> [MPGInterval] {
        let range = (vehicleType ?? fuelLogs.first?.vehicle?.vehicleType ?? .car).plausibleMPGRange
        let missingOdometer = fuelLogs.filter { $0.mileage <= 0 }
        let sortedLogs = fuelLogs
            .filter { $0.mileage > 0 }
            .sorted { ($0.mileage, $0.date) < ($1.mileage, $1.date) }
        let fullTankIndices = sortedLogs.indices.filter { sortedLogs[$0].isFullTank }
        guard fullTankIndices.count >= 2 else { return [] }

        var results: [MPGInterval] = []
        for i in 1..<fullTankIndices.count {
            let startIndex = fullTankIndices[i - 1]
            let endIndex = fullTankIndices[i]
            let startLog = sortedLogs[startIndex]
            let endLog = sortedLogs[endIndex]
            let stretch = sortedLogs[(startIndex + 1)...endIndex]

            let milesDriven = endLog.mileage - startLog.mileage
            // `!(x > 0)` also catches NaN, which `x <= 0` would not.
            let gallonsUsed = stretch.reduce(0.0) { $0 + ($1.gallons > 0 ? $1.gallons : 0) }
            let canCalculate = milesDriven > 0 && gallonsUsed > 0
            let mpg = canCalculate ? Double(milesDriven) / gallonsUsed : 0

            let issue: MPGIssue?
            if milesDriven <= 0 {
                issue = .noDistance
            } else if stretch.contains(where: { !($0.gallons > 0) }) {
                issue = .missingFuelAmount
            } else if missingOdometer.contains(where: { $0.date > startLog.date && $0.date <= endLog.date }) {
                issue = .missingOdometerInStretch
            } else if !range.contains(mpg) {
                issue = .outsideRangeForVehicleType(range)
            } else {
                issue = nil
            }

            results.append(MPGInterval(
                startLog: startLog,
                endLog: endLog,
                milesDriven: milesDriven,
                gallonsUsed: gallonsUsed,
                mpg: mpg,
                issue: issue
            ))
        }
        return results
    }

    /// Splits every interval into "plausible" and "flagged" in one pass,
    /// using two layers of checking:
    /// 1. Structural problems and the vehicle-type sanity range.
    /// 2. This vehicle's own typical MPG. An interval more than 75% above,
    ///    or 50% below, the vehicle's median gets flagged even if it's
    ///    within the type range. This only applies once there are at least
    ///    3 otherwise-good intervals to establish a median.
    private static func classify(for fuelLogs: [FuelLog], vehicleType: VehicleType?) -> (plausible: [MPGInterval], flagged: [MPGInterval]) {
        let all = intervals(for: fuelLogs, vehicleType: vehicleType)
        let candidates = all.filter(\.isPlausible)
        var flagged = all.filter { !$0.isPlausible }

        guard candidates.count >= 3 else {
            return (candidates, flagged)
        }

        let typical = medianMPG(candidates.map(\.mpg))
        let bounds = (typical * 0.5)...(typical * 1.75)

        var plausible: [MPGInterval] = []
        for var interval in candidates {
            if bounds.contains(interval.mpg) {
                plausible.append(interval)
            } else {
                interval.issue = .unusualForThisVehicle(median: typical)
                flagged.append(interval)
            }
        }
        flagged.sort { $0.endLog.mileage < $1.endLog.mileage }
        return (plausible, flagged)
    }

    /// True median (averages the middle two for an even count).
    private static func medianMPG(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Only the intervals that pass every check. Average/Last/Best MPG and
    /// the Reports charts should use this, so one bad data point can't
    /// silently distort them.
    static func plausibleIntervals(for fuelLogs: [FuelLog], vehicleType: VehicleType? = nil) -> [MPGInterval] {
        classify(for: fuelLogs, vehicleType: vehicleType).plausible
    }

    /// The intervals that got excluded, each with an `issue` explaining
    /// why, so the person can fix the underlying entry. Excludes anything
    /// already marked ignored.
    static func flaggedIntervals(for fuelLogs: [FuelLog], vehicleType: VehicleType? = nil) -> [MPGInterval] {
        classify(for: fuelLogs, vehicleType: vehicleType).flagged.filter { !$0.endLog.mpgWarningIgnored }
    }

    /// Fuel logs with no odometer reading. They can't take part in MPG and
    /// should be listed in Data Quality so the person can fill them in.
    static func logsMissingOdometer(for fuelLogs: [FuelLog]) -> [FuelLog] {
        fuelLogs.filter { $0.mileage <= 0 }.sorted { $0.date < $1.date }
    }

    /// Clears "ignore" on the intervals an edit could have changed, so a
    /// new problem can't hide behind an old dismissal. Call after
    /// inserting, editing, or deleting a fuel log. For edits, pass both the
    /// old and new odometer readings.
    ///
    /// The interval containing a reading ends at the next full tank at or
    /// after it. If the changed log is itself a full tank, the interval
    /// after it is affected too, so the next two full tanks are cleared.
    /// That may occasionally clear one extra dismissal, which is the safe
    /// direction.
    static func resetIgnoredWarnings(affectedBy mileages: [Int], in fuelLogs: [FuelLog]) {
        let fullTanks = fuelLogs
            .filter { $0.isFullTank && $0.mileage > 0 }
            .sorted { ($0.mileage, $0.date) < ($1.mileage, $1.date) }
        for mileage in mileages where mileage > 0 {
            for log in fullTanks.drop(while: { $0.mileage < mileage }).prefix(2) {
                log.mpgWarningIgnored = false
            }
        }
    }
}
