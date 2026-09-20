import Foundation

/// Builds CSV files for the Export & Share feature.
/// Explicitly marked `nonisolated` on every member — this project defaults
/// new types to main-actor isolation, which otherwise causes a build error
/// when one function (like csvEscape) is called from inside another
/// (like csv(from:)) via a higher-order function such as .map(_:).
enum CSVGenerator {
    nonisolated static func maintenanceHistoryCSV(vehicle: Vehicle, unit: DistanceUnit) -> String {
        // CSV can't embed the actual photo — but staying silent about it
        // makes it look like the record has no receipt at all when it does.
        // Flagging it here means nothing is lost without your knowledge;
        // the PDF export is what actually embeds the image.
        var rows: [[String]] = [["Date", "Type", "Title", "Mileage (\(unit.rawValue))", "Cost", "Notes", "Has Receipt Photo"]]
        for record in vehicle.maintenanceRecords.sorted(by: { $0.date > $1.date }) {
            rows.append([
                record.date.formatted(date: .abbreviated, time: .omitted),
                record.type.rawValue,
                record.title,
                String(convertFromMiles(record.mileage, to: unit)),
                String(format: "%.2f", record.cost),
                record.notes,
                record.receiptPhotoData != nil ? "Yes" : "No"
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
