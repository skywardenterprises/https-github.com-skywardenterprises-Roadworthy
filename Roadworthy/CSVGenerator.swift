import Foundation

/// Builds CSV files for the Export & Share feature.
/// Explicitly marked `nonisolated` on every member — this project defaults
/// new types to main-actor isolation, which otherwise causes a build error
/// when one function (like csvEscape) is called from inside another
/// (like csv(from:)) via a higher-order function such as .map(_:).
///
/// Format choices, so the file works in spreadsheets and can be read back
/// by a program later:
/// - Dates are `yyyy-MM-dd` in the device's time zone, not the display
///   format ("Sep 22, 2026" or "22 sept. 2026" can't be parsed reliably).
/// - Mileage is always in miles (how it's stored). Kilometer users also
///   get a km column.
/// - Lines end with CRLF, per the CSV standard (RFC 4180).
/// - The UTF-8 byte-order mark is added by ExportView when the file is
///   written, so Excel shows accented and non-Latin text correctly.
enum CSVGenerator {
    nonisolated static func maintenanceHistoryCSV(vehicle: Vehicle, unit: DistanceUnit) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let includeKilometers = unit == .kilometers

        // CSV can't embed the actual photo — but staying silent about it
        // makes it look like the record has no receipt at all when it does.
        // Flagging it here means nothing is lost without your knowledge;
        // the PDF export is what actually embeds the image.
        var header = ["Date", "Vehicle", "Type", "Title", "Mileage (mi)"]
        if includeKilometers { header.append("Mileage (km)") }
        header += ["Cost", "Shop", "Notes", "Has Receipt Photo"]

        // Columns holding free text, which get spreadsheet-formula protection.
        // Numeric columns are left alone so values like -5 aren't altered.
        var textColumns: Set<Int> = [1, 2, 3]
        let offset = includeKilometers ? 1 : 0
        textColumns.formUnion([6 + offset, 7 + offset])

        var rows: [[String]] = [header]
        for record in vehicle.maintenanceRecords.sorted(by: { $0.date > $1.date }) {
            var row = [
                dateFormatter.string(from: record.date),
                vehicle.displayName,
                record.type.rawValue,
                record.title,
                record.mileage > 0 ? String(record.mileage) : ""
            ]
            if includeKilometers {
                row.append(record.mileage > 0 ? String(convertFromMiles(record.mileage, to: .kilometers)) : "")
            }
            row += [
                String(format: "%.2f", record.cost),
                record.shopName,
                record.notes,
                record.receiptPhotoData != nil ? "Yes" : "No"
            ]
            rows.append(row)
        }
        return csv(from: rows, textColumns: textColumns)
    }

    nonisolated private static func csv(from rows: [[String]], textColumns: Set<Int>) -> String {
        rows.enumerated().map { rowIndex, row in
            row.enumerated().map { columnIndex, field in
                // The header row is never formula-protected.
                let protect = rowIndex > 0 && textColumns.contains(columnIndex)
                return csvEscape(protect ? neutralizeFormula(field) : field)
            }
            .joined(separator: ",")
        }
        .joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field if it contains a comma, quote, or line break. Checks
    /// Unicode scalars, because Swift treats "\r\n" as a single Character,
    /// which `contains("\n")` doesn't match, and a lone "\r" wasn't checked
    /// at all before.
    nonisolated private static func csvEscape(_ field: String) -> String {
        let needsQuoting = field.unicodeScalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\n" || scalar == "\r"
        }
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Spreadsheets run a field starting with =, +, -, or @ as a formula.
    /// Prefixing an apostrophe makes it display as plain text. Applied to
    /// text columns only.
    nonisolated private static func neutralizeFormula(_ field: String) -> String {
        guard let first = field.unicodeScalars.first else { return field }
        let triggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        return triggers.contains(first) ? "'" + field : field
    }
}
