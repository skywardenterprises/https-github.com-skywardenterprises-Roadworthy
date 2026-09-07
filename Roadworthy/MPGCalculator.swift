import Foundation

/// One "full tank to full tank" stretch, with the MPG calculated for it.
struct MPGInterval: Identifiable {
    let id = UUID()
    let startLog: FuelLog
    let endLog: FuelLog
    let milesDriven: Int
    let gallonsUsed: Double
    let mpg: Double

    /// Realistic range for essentially any consumer vehicle. Anything
    /// outside this almost certainly means something's off in the
    /// underlying data — a typo in an odometer reading, a fill-up
    /// misclassified as full/partial, or a fill-up that was never logged
    /// at all (common with older, imported data).
    static let plausibleRange = 8.0...75.0

    var isPlausible: Bool {
        MPGInterval.plausibleRange.contains(mpg)
    }
}

enum MPGCalculator {
    /// Every full-tank-to-full-tank interval found in the given fuel logs,
    /// plausible or not. Gallons used correctly includes every fill-up in
    /// the stretch (partial fill-ups included), not just the ending
    /// full-tank fill-up.
    static func intervals(for fuelLogs: [FuelLog]) -> [MPGInterval] {
        let sortedLogs = fuelLogs.sorted { $0.mileage < $1.mileage }
        let fullTankIndices = sortedLogs.indices.filter { sortedLogs[$0].isFullTank }
        guard fullTankIndices.count >= 2 else { return [] }

        var results: [MPGInterval] = []
        for i in 1..<fullTankIndices.count {
            let startIndex = fullTankIndices[i - 1]
            let endIndex = fullTankIndices[i]
            let startLog = sortedLogs[startIndex]
            let endLog = sortedLogs[endIndex]
            let milesDriven = endLog.mileage - startLog.mileage
            let gallonsUsed = sortedLogs[(startIndex + 1)...endIndex].reduce(0.0) { $0 + $1.gallons }
            guard gallonsUsed > 0, milesDriven > 0 else { continue }
            results.append(MPGInterval(
                startLog: startLog,
                endLog: endLog,
                milesDriven: milesDriven,
                gallonsUsed: gallonsUsed,
                mpg: Double(milesDriven) / gallonsUsed
            ))
        }
        return results
    }

    /// Splits every interval into "plausible" and "flagged," in one pass —
    /// this uses two layers of checking:
    /// 1. A universal sanity range (8-75 MPG) that catches wildly broken
    ///    values regardless of vehicle.
    /// 2. A check against THIS vehicle's own typical MPG — since a value
    ///    can be realistic for cars in general (like 40 or 65 MPG) while
    ///    still being impossible for one specific vehicle (like a V6 SUV
    ///    that has never once actually gotten close to that on any other
    ///    fill-up). An interval more than 75% above, or 50% below, this
    ///    vehicle's own median gets flagged even if it's within the
    ///    universal range.
    private static func classify(for fuelLogs: [FuelLog]) -> (plausible: [MPGInterval], flagged: [MPGInterval]) {
        let all = intervals(for: fuelLogs)
        let withinUniversalRange = all.filter(\.isPlausible)
        let outsideUniversalRange = all.filter { !$0.isPlausible }

        // Not enough data yet to establish what's "typical" for this
        // vehicle — fall back to the universal range alone.
        guard withinUniversalRange.count >= 3 else {
            return (withinUniversalRange, outsideUniversalRange)
        }

        let sortedMPGs = withinUniversalRange.map(\.mpg).sorted()
        let median = sortedMPGs[sortedMPGs.count / 2]
        let lowerBound = median * 0.5
        let upperBound = median * 1.75

        let plausible = withinUniversalRange.filter { $0.mpg >= lowerBound && $0.mpg <= upperBound }
        let relativeOutliers = withinUniversalRange.filter { $0.mpg < lowerBound || $0.mpg > upperBound }

        return (plausible, outsideUniversalRange + relativeOutliers)
    }

    /// Only the intervals that are plausible both universally and for this
    /// specific vehicle — this is what Average/Last/Best MPG and the
    /// Reports charts should actually use, so one bad data point can't
    /// silently distort them.
    static func plausibleIntervals(for fuelLogs: [FuelLog]) -> [MPGInterval] {
        classify(for: fuelLogs).plausible
    }

    /// The intervals that got excluded — surfaced to the person so they can
    /// actually go fix the underlying entry instead of the bad data just
    /// silently disappearing. Excludes anything already marked ignored.
    static func flaggedIntervals(for fuelLogs: [FuelLog]) -> [MPGInterval] {
        classify(for: fuelLogs).flagged.filter { !$0.endLog.mpgWarningIgnored }
    }
}
