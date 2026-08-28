import SwiftUI
import Charts

private enum ChartPeriod: String, CaseIterable, Identifiable {
    case fillUp = "Per Fill-Up"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    var id: String { rawValue }
}

private enum BreakdownRange: String, CaseIterable, Identifiable {
    case allTime = "All Time"
    case thisYear = "This Year"
    case thisMonth = "This Month"
    var id: String { rawValue }
}

private enum ComparisonPeriod: String, CaseIterable, Identifiable {
    case month = "Month vs Last Month"
    case year = "Year vs Last Year"
    var id: String { rawValue }
}

private enum ComparisonMetric: String, CaseIterable, Identifiable {
    case mpg = "MPG"
    case costPerGallon = "Cost / Gallon"
    var id: String { rawValue }
}

struct ReportsView: View {
    let vehicle: Vehicle

    @State private var fuelChartPeriod: ChartPeriod = .fillUp
    @State private var breakdownRange: BreakdownRange = .allTime
    @State private var comparisonPeriod: ComparisonPeriod = .month
    @State private var comparisonMetric: ComparisonMetric = .mpg

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                quickStatsSection
                fuelTrendsSection
                spendingBreakdownSection
                costPerMileSection
                comparisonSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Raw data points

    private struct MPGPoint {
        let date: Date
        let mpg: Double
    }

    // MPG per fill-up, calculated from the gap between consecutive full-tank fill-ups.
    private var mpgPoints: [MPGPoint] {
        let fullTankLogs = vehicle.fuelLogs.filter { $0.isFullTank }.sorted { $0.mileage < $1.mileage }
        guard fullTankLogs.count >= 2 else { return [] }
        var points: [MPGPoint] = []
        for i in 1..<fullTankLogs.count {
            let milesDriven = Double(fullTankLogs[i].mileage - fullTankLogs[i - 1].mileage)
            let gallonsUsed = fullTankLogs[i].gallons
            guard gallonsUsed > 0, milesDriven > 0 else { continue }
            points.append(MPGPoint(date: fullTankLogs[i].date, mpg: milesDriven / gallonsUsed))
        }
        return points
    }

    private var pricePoints: [(date: Date, price: Double)] {
        vehicle.fuelLogs.sorted { $0.date < $1.date }.map { (date: $0.date, price: $0.pricePerGallon) }
    }

    // MARK: - Aggregation (Per Fill-Up / Week / Month / Year)

    private struct AggregatedPoint: Identifiable {
        let id = UUID()
        let label: String
        let date: Date
        let value: Double
    }

    private func aggregate(_ raw: [(date: Date, value: Double)], by period: ChartPeriod) -> [AggregatedPoint] {
        if period == .fillUp {
            return raw
                .sorted { $0.date < $1.date }
                .map { AggregatedPoint(label: $0.date.formatted(date: .abbreviated, time: .omitted), date: $0.date, value: $0.value) }
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: raw) { entry -> DateComponents in
            switch period {
            case .week:
                return calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
            case .month:
                return calendar.dateComponents([.year, .month], from: entry.date)
            case .year:
                return calendar.dateComponents([.year], from: entry.date)
            case .fillUp:
                return DateComponents()
            }
        }

        let aggregated: [AggregatedPoint] = grouped.map { _, entries in
            // Use the earliest date in the bucket as the representative x-position —
            // safer than reconstructing a Date from partial components.
            let representativeDate = entries.map(\.date).min() ?? .now
            let average = entries.reduce(0) { $0 + $1.value } / Double(entries.count)
            let label: String
            switch period {
            case .week:
                label = representativeDate.formatted(.dateTime.month(.abbreviated).day())
            case .month:
                label = representativeDate.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
            case .year:
                label = representativeDate.formatted(.dateTime.year())
            case .fillUp:
                label = ""
            }
            return AggregatedPoint(label: label, date: representativeDate, value: average)
        }

        return aggregated.sorted { $0.date < $1.date }
    }

    private var mpgAggregated: [AggregatedPoint] {
        aggregate(mpgPoints.map { (date: $0.date, value: $0.mpg) }, by: fuelChartPeriod)
    }
    private var priceAggregated: [AggregatedPoint] {
        aggregate(pricePoints, by: fuelChartPeriod)
    }

    // MARK: - Summary totals

    private var totalFuelCost: Double { vehicle.fuelLogs.reduce(0) { $0 + $1.totalCost } }
    private var totalMaintenanceCost: Double { vehicle.maintenanceRecords.reduce(0) { $0 + $1.cost } }
    private var totalExpenseCost: Double { vehicle.expenses.reduce(0) { $0 + $1.amount } }
    private var totalSpend: Double { totalFuelCost + totalMaintenanceCost + totalExpenseCost }

    private var overallCostPerMile: Double? {
        guard vehicle.currentMileage > 0 else { return nil }
        return totalSpend / Double(vehicle.currentMileage)
    }
    private var overallAverageMPG: Double? {
        guard !mpgPoints.isEmpty else { return nil }
        return mpgPoints.reduce(0) { $0 + $1.mpg } / Double(mpgPoints.count)
    }

    // MARK: - Section 1: Summary

    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("SUMMARY")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard(value: overallAverageMPG.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", label: "AVG MPG")
                statCard(value: overallCostPerMile.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(2))) } ?? "—", label: "COST / MILE")
                statCard(value: totalSpend.formatted(.currency(code: "USD").precision(.fractionLength(0))), label: "TOTAL SPEND")
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Section 2: Fuel Trends (MPG + Cost/Gallon)

    private var fuelTrendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("FUEL TRENDS")
            Picker("Period", selection: $fuelChartPeriod) {
                ForEach(ChartPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text("MPG").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                if mpgAggregated.isEmpty {
                    emptyChartPlaceholder("Log at least two full-tank fill-ups to see MPG trends.")
                        .padding(.horizontal, 16)
                } else {
                    Chart(mpgAggregated) { point in
                        LineMark(x: .value("Date", point.date), y: .value("MPG", point.value))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value("MPG", point.value))
                    }
                    .frame(height: 180)
                    .padding(.horizontal, 16)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Cost / Gallon").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                if priceAggregated.isEmpty {
                    emptyChartPlaceholder("Log a few fill-ups to see fuel price trends.")
                        .padding(.horizontal, 16)
                } else {
                    Chart(priceAggregated) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Price", point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                        PointMark(x: .value("Date", point.date), y: .value("Price", point.value))
                            .foregroundStyle(.orange)
                    }
                    .frame(height: 180)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Section 3: Spending Breakdown

    private func breakdownRangeDates() -> ClosedRange<Date> {
        let now = Date.now
        let calendar = Calendar.current
        switch breakdownRange {
        case .allTime:
            return Date.distantPast...Date.distantFuture
        case .thisYear:
            let start = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
            return start...Date.distantFuture
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return start...Date.distantFuture
        }
    }

    private var breakdownData: [(category: String, amount: Double, color: Color)] {
        let range = breakdownRangeDates()
        let fuel = vehicle.fuelLogs.filter { range.contains($0.date) }.reduce(0) { $0 + $1.totalCost }
        let maintenance = vehicle.maintenanceRecords.filter { range.contains($0.date) }.reduce(0) { $0 + $1.cost }
        let expenses = vehicle.expenses.filter { range.contains($0.date) }.reduce(0) { $0 + $1.amount }
        return [
            ("Fuel", fuel, Color.blue),
            ("Maintenance", maintenance, Color.orange),
            ("Expenses", expenses, Color.green)
        ]
    }

    private var spendingBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("SPENDING BREAKDOWN")
            Picker("Range", selection: $breakdownRange) {
                ForEach(BreakdownRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            let data = breakdownData.filter { $0.amount > 0 }
            if data.isEmpty {
                emptyChartPlaceholder("No spending logged in this range yet.")
                    .padding(.horizontal, 16)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(data, id: \.category) { item in
                        SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(item.color)
                    }
                    .frame(width: 140, height: 140)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(data, id: \.category) { item in
                            HStack {
                                Circle().fill(item.color).frame(width: 8, height: 8)
                                Text(item.category).font(.caption)
                                Spacer()
                                Text(item.amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Section 4: Cost Per Mile (monthly)

    private struct MileageSnapshot {
        let date: Date
        let mileage: Int
    }

    private var mileageSnapshots: [MileageSnapshot] {
        let fromFuel = vehicle.fuelLogs.map { MileageSnapshot(date: $0.date, mileage: $0.mileage) }
        let fromMaintenance = vehicle.maintenanceRecords.map { MileageSnapshot(date: $0.date, mileage: $0.mileage) }
        return (fromFuel + fromMaintenance).sorted { $0.date < $1.date }
    }

    private func mileageAtOrBefore(_ date: Date) -> Int? {
        mileageSnapshots.last { $0.date <= date }?.mileage
    }

    private func totalSpend(from start: Date, through end: Date) -> Double {
        let range = start...end
        let fuel = vehicle.fuelLogs.filter { range.contains($0.date) }.reduce(0) { $0 + $1.totalCost }
        let maintenance = vehicle.maintenanceRecords.filter { range.contains($0.date) }.reduce(0) { $0 + $1.cost }
        let expenses = vehicle.expenses.filter { range.contains($0.date) }.reduce(0) { $0 + $1.amount }
        return fuel + maintenance + expenses
    }

    private struct MonthCostPerMile: Identifiable {
        let id = UUID()
        let monthStart: Date
        let costPerMile: Double
    }

    private var monthlyCostPerMile: [MonthCostPerMile] {
        let allDates = vehicle.fuelLogs.map { $0.date } + vehicle.maintenanceRecords.map { $0.date } + vehicle.expenses.map { $0.date }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else { return [] }

        let calendar = Calendar.current
        var months: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: minDate)) ?? minDate
        let end = calendar.date(from: calendar.dateComponents([.year, .month], from: maxDate)) ?? maxDate
        while cursor <= end {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        var results: [MonthCostPerMile] = []
        for monthStart in months {
            guard let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else { continue }
            let spend = totalSpend(from: monthStart, through: monthEnd)
            guard let endMileage = mileageAtOrBefore(monthEnd),
                  let startMileage = mileageAtOrBefore(monthStart.addingTimeInterval(-1)),
                  endMileage > startMileage else { continue }
            let miles = endMileage - startMileage
            results.append(MonthCostPerMile(monthStart: monthStart, costPerMile: spend / Double(miles)))
        }
        return results
    }

    private var costPerMileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("COST PER MILE (MONTHLY)")
            if monthlyCostPerMile.isEmpty {
                emptyChartPlaceholder("Log fill-ups or maintenance across at least two different months to see this trend.")
                    .padding(.horizontal, 16)
            } else {
                Chart(monthlyCostPerMile) { point in
                    BarMark(
                        x: .value("Month", point.monthStart, unit: .month),
                        y: .value("Cost/Mile", point.costPerMile)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 180)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Section 5: Period Comparison

    private struct ComparisonSeries: Identifiable {
        let id = UUID()
        let label: String
        let index: Int
        let value: Double
    }

    private var comparisonData: [ComparisonSeries] {
        let calendar = Calendar.current
        let now = Date.now

        let rawPoints: [(date: Date, value: Double)] = comparisonMetric == .mpg
            ? mpgPoints.map { (date: $0.date, value: $0.mpg) }
            : pricePoints

        switch comparisonPeriod {
        case .month:
            let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? currentStart

            var series: [ComparisonSeries] = []
            for point in rawPoints where point.date >= currentStart {
                let day = calendar.component(.day, from: point.date)
                series.append(ComparisonSeries(label: "This Month", index: day, value: point.value))
            }
            for point in rawPoints where point.date >= previousStart && point.date <= previousEnd {
                let day = calendar.component(.day, from: point.date)
                series.append(ComparisonSeries(label: "Last Month", index: day, value: point.value))
            }
            return series

        case .year:
            let currentYear = calendar.component(.year, from: now)
            var series: [ComparisonSeries] = []
            for point in rawPoints {
                let year = calendar.component(.year, from: point.date)
                let month = calendar.component(.month, from: point.date)
                if year == currentYear {
                    series.append(ComparisonSeries(label: "This Year", index: month, value: point.value))
                } else if year == currentYear - 1 {
                    series.append(ComparisonSeries(label: "Last Year", index: month, value: point.value))
                }
            }
            return series
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PERIOD COMPARISON")
            Picker("Metric", selection: $comparisonMetric) {
                ForEach(ComparisonMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            Picker("Period", selection: $comparisonPeriod) {
                ForEach(ComparisonPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if comparisonData.isEmpty {
                emptyChartPlaceholder("Not enough data yet to compare these periods.")
                    .padding(.horizontal, 16)
            } else {
                Chart(comparisonData) { point in
                    LineMark(
                        x: .value(comparisonPeriod == .month ? "Day" : "Month", point.index),
                        y: .value(comparisonMetric.rawValue, point.value)
                    )
                    .foregroundStyle(by: .value("Period", point.label))
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Shared helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func emptyChartPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
