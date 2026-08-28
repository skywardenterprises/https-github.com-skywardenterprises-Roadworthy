import Foundation

/// Builds CSV files for the Export & Share feature. Kept in its own file
/// (Foundation only, no UIKit) so it isn't affected by the main-actor
/// isolation Swift infers for types that use UIKit, like ExportGenerator.
enum CSVGenerator {
    static func maintenanceHistoryCSV(vehicle: Vehicle) -> String {
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

    private static func csv(from rows: [[String]]) -> String {
        rows.map { row in row.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
