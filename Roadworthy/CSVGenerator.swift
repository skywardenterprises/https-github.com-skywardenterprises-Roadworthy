import Foundation

/// Builds CSV files for the Export & Share feature.
/// Explicitly marked `nonisolated` on every member — this project defaults
/// new types to main-actor isolation, which otherwise causes a build error
/// when one function (like csvEscape) is called from inside another
/// (like csv(from:)) via a higher-order function such as .map(_:).
enum CSVGenerator {
    nonisolated static func maintenanceHistoryCSV(vehicle: Vehicle) -> String {
        var rows: [[String]] = [["Date", "Type", "Title", "Mileage", "Cost", "Notes"]]
        for record in vehicle.maintenanceRecords.sorted(by: { $0.date > $1.date }) {
            rows.append([
                record.date.formatted(date: .abbreviated, time: .omitted),
                record.type.rawValue,
                record.title,
                String(record.mileage),
                String(format: "%.2f", record.cost),
                record.notes
            ])
        }
        return csv(from: rows)
    }

    nonisolated private static func csv(from rows: [[String]]) -> String {
        rows.map { row in row.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
    }

    nonisolated private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
