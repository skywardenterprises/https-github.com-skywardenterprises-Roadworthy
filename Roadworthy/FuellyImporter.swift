import Foundation

/// A fuel-up parsed from an import file, not yet attached to a specific
/// Roadworthy Vehicle — that happens once the person matches or creates a
/// vehicle for it in the import flow.
struct ImportedFuelEntry {
    let vehicleName: String
    let date: Date
    let mileage: Int
    let gallons: Double
    let pricePerGallon: Double
    let totalCost: Double
    let isFullTank: Bool
    let fuelGrade: FuelGrade
    let stationName: String
    let paymentMethod: FuelPaymentMethod
    let notes: String
}

/// A maintenance record parsed from an import file, same deal as above.
struct ImportedMaintenanceEntry {
    let vehicleName: String
    let date: Date
    let mileage: Int
    let cost: Double
    let title: String
    let type: MaintenanceType
    let notes: String
}

struct ImportResult {
    let fuelEntries: [ImportedFuelEntry]
    let maintenanceEntries: [ImportedMaintenanceEntry]
    /// Unique vehicle names, in the order they first appear in the file.
    let vehicleNames: [String]
}

enum FuellyImporter {
    static func parse(csvText: String) -> ImportResult {
        let rows = parseCSVRows(csvText)
        guard let header = rows.first else {
            return ImportResult(fuelEntries: [], maintenanceEntries: [], vehicleNames: [])
        }

        func columnIndex(_ name: String) -> Int? {
            header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        guard
            let typeCol = columnIndex("Type"),
            let dateCol = columnIndex("Date"),
            let timeCol = columnIndex("Time"),
            let vehicleCol = columnIndex("Vehicle"),
            let odometerCol = columnIndex("Odometer"),
            let filledUpCol = columnIndex("Filled Up"),
            let pricePerGallonCol = columnIndex("Cost/Gallon"),
            let gallonsCol = columnIndex("Gallons"),
            let totalCostCol = columnIndex("Total Cost"),
            let octaneCol = columnIndex("Octane"),
            let gasBrandCol = columnIndex("Gas Brand"),
            let locationCol = columnIndex("Location"),
            let paymentTypeCol = columnIndex("Payment Type"),
            let notesCol = columnIndex("Notes"),
            let servicesCol = columnIndex("Services")
        else {
            return ImportResult(fuelEntries: [], maintenanceEntries: [], vehicleNames: [])
        }

        var fuelEntries: [ImportedFuelEntry] = []
        var maintenanceEntries: [ImportedMaintenanceEntry] = []
        var vehicleNames: [String] = []

        for row in rows.dropFirst() {
            guard row.count > servicesCol else { continue }

            let vehicleName = row[vehicleCol].trimmingCharacters(in: .whitespaces)
            guard !vehicleName.isEmpty else { continue }
            if !vehicleNames.contains(vehicleName) {
                vehicleNames.append(vehicleName)
            }

            let date = parseDate(dateString: row[dateCol], timeString: row[timeCol])
            let mileage = parseOdometer(row[odometerCol])

            let recordType = row[typeCol].trimmingCharacters(in: .whitespaces)

            if recordType.caseInsensitiveCompare("Gas") == .orderedSame {
                let filledUp = row[filledUpCol].trimmingCharacters(in: .whitespaces)
                let stationName = combinedStationName(brand: row[gasBrandCol], location: row[locationCol])
                let entry = ImportedFuelEntry(
                    vehicleName: vehicleName,
                    date: date,
                    mileage: mileage,
                    gallons: parseDollarOrPlainNumber(row[gallonsCol]),
                    pricePerGallon: parseDollarOrPlainNumber(row[pricePerGallonCol]),
                    totalCost: parseDollarOrPlainNumber(row[totalCostCol]),
                    isFullTank: filledUp.caseInsensitiveCompare("Full") == .orderedSame,
                    fuelGrade: parseFuelGrade(row[octaneCol]),
                    stationName: stationName,
                    paymentMethod: parsePaymentMethod(row[paymentTypeCol]),
                    notes: row[notesCol].trimmingCharacters(in: .whitespaces)
                )
                fuelEntries.append(entry)
            } else if recordType.caseInsensitiveCompare("Service") == .orderedSame {
                let servicesText = row[servicesCol].trimmingCharacters(in: .whitespaces)
                guard !servicesText.isEmpty else { continue }
                let shopName = combinedStationName(brand: row[gasBrandCol], location: row[locationCol])
                let entry = ImportedMaintenanceEntry(
                    vehicleName: vehicleName,
                    date: date,
                    mileage: mileage,
                    cost: parseDollarOrPlainNumber(row[totalCostCol]),
                    title: servicesText,
                    type: inferMaintenanceType(from: servicesText),
                    notes: shopName.isEmpty ? "" : "Shop: \(shopName)"
                )
                maintenanceEntries.append(entry)
            }
        }

        return ImportResult(fuelEntries: fuelEntries, maintenanceEntries: maintenanceEntries, vehicleNames: vehicleNames)
    }

    // MARK: - Field parsing helpers

    private static func parseDate(dateString: String, timeString: String) -> Date {
        let combined = "\(dateString) \(timeString)".trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        if let date = formatter.date(from: combined) {
            return date
        }
        // Fall back to just the date if the time couldn't be parsed.
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString.trimmingCharacters(in: .whitespaces)) ?? .now
    }

    private static func parseOdometer(_ raw: String) -> Int {
        let digitsOnly = raw.filter(\.isNumber)
        return Int(digitsOnly) ?? 0
    }

    private static func parseDollarOrPlainNumber(_ raw: String) -> Double {
        let cleaned = raw.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    private static func combinedStationName(brand: String, location: String) -> String {
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let location = location.trimmingCharacters(in: .whitespaces)
        // Skip anything that's just a stray number — seen in some Fuelly
        // exports as a data-entry glitch in the Gas Brand field.
        let cleanBrand = brand.allSatisfy(\.isNumber) ? "" : brand
        if !cleanBrand.isEmpty && !location.isEmpty && cleanBrand != location {
            return "\(cleanBrand) — \(location)"
        }
        return cleanBrand.isEmpty ? location : cleanBrand
    }

    private static func parseFuelGrade(_ raw: String) -> FuelGrade {
        let lower = raw.lowercased()
        if lower.contains("premium") { return .premium }
        if lower.contains("mid-grade") || lower.contains("mid grade") || lower.contains("plus") { return .midGrade }
        if lower.contains("diesel") { return .diesel }
        if lower.contains("e85") { return .e85 }
        // Covers both "Regular" and "Low [Octane: 85]" (common in
        // high-altitude states where base-grade gas is sold at 85 octane).
        return .regular
    }

    private static func parsePaymentMethod(_ raw: String) -> FuelPaymentMethod {
        let lower = raw.lowercased()
        if lower.contains("cash") { return .cash }
        if lower.contains("debit") { return .debitCard }
        if lower.isEmpty { return .creditCard }
        // VISA, Mastercard, Amex, Discover, and anything else free-typed
        // into Fuelly's payment field is treated as a credit card.
        return .creditCard
    }

    private static func inferMaintenanceType(from servicesText: String) -> MaintenanceType {
        let lower = servicesText.lowercased()
        if lower.contains("oil") { return .oilChange }
        if lower.contains("tire rotation") { return .tireRotation }
        if lower.contains("tire") { return .tireReplacement }
        if lower.contains("brake") { return .brakes }
        if lower.contains("battery") { return .battery }
        if lower.contains("air filter") { return .airFilter }
        if lower.contains("registration") || lower.contains("license") || lower.contains("tag") { return .registration }
        if lower.contains("inspect") { return .inspection }
        if lower.contains("fluid") || lower.contains("coolant") || lower.contains("power steering") { return .fluids }
        return .other
    }

    // MARK: - CSV parsing (handles quoted fields containing commas, e.g. "FWB, FL")

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        let characters = Array(text)
        var i = 0
        while i < characters.count {
            let char = characters[i]
            if insideQuotes {
                if char == "\"" {
                    if i + 1 < characters.count && characters[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else if char == "\"" {
                insideQuotes = true
            } else if char == "," {
                currentRow.append(currentField)
                currentField = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r" && i + 1 < characters.count && characters[i + 1] == "\n" {
                    i += 1
                }
                currentRow.append(currentField)
                if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }
}
