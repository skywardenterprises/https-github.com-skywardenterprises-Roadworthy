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

    /// Only the intervals that fall within a realistic MPG range — this is
    /// what Average/Last/Best MPG and the Reports charts should actually
    /// use, so one bad data point can't silently distort them.
    static func plausibleIntervals(for fuelLogs: [FuelLog]) -> [MPGInterval] {
        intervals(for: fuelLogs).filter(\.isPlausible)
    }

    /// The intervals that got excluded for being implausible — surfaced to
    /// the person so they can actually go fix the underlying entry instead
    /// of the bad data just silently disappearing.
    static func flaggedIntervals(for fuelLogs: [FuelLog]) -> [MPGInterval] {
        intervals(for: fuelLogs).filter { !$0.isPlausible }
    }
}
