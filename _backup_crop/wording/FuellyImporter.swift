import Foundation

// MARK: - Import models

/// Why an entry was flagged as a possible duplicate. Flagged entries are
/// excluded from import by default, and the person can turn any of them
/// back on.
enum ImportDuplicateReason: Equatable {
    /// Matches an earlier row in this same file. Only the later copy is
    /// flagged; the earlier row is always kept.
    case earlierRowInFile(row: Int)
    /// Matches a record already saved on the vehicle this entry is being
    /// imported into (for example, the same file imported twice).
    case alreadyOnVehicle

    var description: String {
        switch self {
        case .earlierRowInFile(let row): return "Same as row \(row) in this file"
        case .alreadyOnVehicle: return "Already saved on this vehicle"
        }
    }
}

/// A row that couldn't be turned into an entry at all, with the reason.
/// Shown to the person so nothing disappears silently.
struct ImportSkippedRow: Identifiable {
    let id = UUID()
    let row: Int
    let reason: String
}

/// A fuel-up parsed from an import file, not yet attached to a specific
/// Roadworthy Vehicle. That happens once the person matches or creates a
/// vehicle for it in the import flow.
struct ImportedFuelEntry {
    /// Row number in the source file (header = row 1).
    let sourceRow: Int
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
    /// Problems found in the row itself. The entry is still imported, but
    /// these should be shown so the person can review.
    var warnings: [String] = []
    /// Problems found by comparing against the destination vehicle.
    /// Rebuilt every time `FuellyImporter.review` runs.
    var vehicleWarnings: [String] = []
    var duplicateReason: ImportDuplicateReason?

    var isPossibleDuplicate: Bool { duplicateReason != nil }
    var allWarnings: [String] { warnings + vehicleWarnings }
}

/// A maintenance record parsed from an import file, same deal as above.
struct ImportedMaintenanceEntry {
    let sourceRow: Int
    let vehicleName: String
    let date: Date
    /// 0 when the file had no odometer reading (a warning is attached).
    let mileage: Int
    let cost: Double
    let title: String
    let type: MaintenanceType
    let shopName: String
    let notes: String
    var warnings: [String] = []
    var vehicleWarnings: [String] = []
    var duplicateReason: ImportDuplicateReason?

    var isPossibleDuplicate: Bool { duplicateReason != nil }
    var allWarnings: [String] { warnings + vehicleWarnings }
}

struct ImportResult {
    var fuelEntries: [ImportedFuelEntry]
    var maintenanceEntries: [ImportedMaintenanceEntry]
    /// Unique vehicle names that produced at least one entry, in the order
    /// they first appear in the file.
    let vehicleNames: [String]
    /// Rows that couldn't be imported, with the reason for each.
    let skippedRows: [ImportSkippedRow]
    /// Set when the file can't be imported at all. Show this message
    /// instead of a generic parse error.
    let fileError: String?

    fileprivate static func failed(_ message: String) -> ImportResult {
        ImportResult(fuelEntries: [], maintenanceEntries: [], vehicleNames: [], skippedRows: [], fileError: message)
    }
}

// MARK: - Duplicate rules

/// One set of duplicate-matching rules for every entry type, so any
/// difference between fuel and maintenance is deliberate and visible here.
///
/// Both types require the same vehicle, the same calendar day, and an
/// odometer reading within `mileageTolerance`. They differ only in the
/// content check:
/// - Fuel: gallons must match. Two different-sized fills on the same stop
///   (a top-off, a jerry can) are separate events.
/// - Maintenance: type and title must match. An oil change and a tire
///   rotation logged separately on the same visit are separate events.
enum ImportDuplicateRules {
    /// Odometer readings within this many miles count as the same reading
    /// (covers rounding and tenths dropped by the source app).
    static let mileageTolerance = 3
    /// Gallons within this amount count as the same fill-up.
    static let gallonsTolerance = 0.05

    static func isSameVisit(dateA: Date, mileageA: Int, dateB: Date, mileageB: Int) -> Bool {
        Calendar.current.isDate(dateA, inSameDayAs: dateB) && abs(mileageA - mileageB) <= mileageTolerance
    }

    static func isSameFill(gallonsA: Double, gallonsB: Double) -> Bool {
        abs(gallonsA - gallonsB) <= gallonsTolerance
    }

    static func isSameService(typeA: MaintenanceType, titleA: String, typeB: MaintenanceType, titleB: String) -> Bool {
        typeA == typeB && normalizedTitle(titleA) == normalizedTitle(titleB)
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

protocol ImportDuplicateCheckable {
    var vehicleName: String { get }
    var sourceRow: Int { get }
    var duplicateReason: ImportDuplicateReason? { get set }
    func isSameEvent(as other: Self) -> Bool
}

extension ImportedFuelEntry: ImportDuplicateCheckable {
    func isSameEvent(as other: ImportedFuelEntry) -> Bool {
        ImportDuplicateRules.isSameVisit(dateA: date, mileageA: mileage, dateB: other.date, mileageB: other.mileage)
            && ImportDuplicateRules.isSameFill(gallonsA: gallons, gallonsB: other.gallons)
    }

    func isSameEvent(as log: FuelLog) -> Bool {
        ImportDuplicateRules.isSameVisit(dateA: date, mileageA: mileage, dateB: log.date, mileageB: log.mileage)
            && ImportDuplicateRules.isSameFill(gallonsA: gallons, gallonsB: log.gallons)
    }
}

extension ImportedMaintenanceEntry: ImportDuplicateCheckable {
    func isSameEvent(as other: ImportedMaintenanceEntry) -> Bool {
        ImportDuplicateRules.isSameVisit(dateA: date, mileageA: mileage, dateB: other.date, mileageB: other.mileage)
            && ImportDuplicateRules.isSameService(typeA: type, titleA: title, typeB: other.type, titleB: other.title)
    }

    func isSameEvent(as record: MaintenanceRecord) -> Bool {
        ImportDuplicateRules.isSameVisit(dateA: date, mileageA: mileage, dateB: record.date, mileageB: record.mileage)
            && ImportDuplicateRules.isSameService(typeA: type, titleA: title, typeB: record.type, titleB: record.title)
    }
}

// MARK: - Importer

enum FuellyImporter {

    // MARK: Parse

    static func parse(csvText: String) -> ImportResult {
        let delimiter = detectDelimiter(csvText)
        let csv = parseCSVRows(csvText, delimiter: delimiter)
        guard let rawHeader = csv.rows.first else {
            return .failed("The file is empty.")
        }
        // Excel in many European regions saves "CSV" with semicolons between
        // fields and commas as decimal points ("12,5"). Numbers in those
        // files are read the same way.
        let decimalComma = delimiter == ";"

        // Trim whitespace and a UTF-8 byte-order mark, which Excel adds and
        // which would otherwise break the "Type" column match.
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        let header = rawHeader.map { $0.trimmingCharacters(in: trimSet) }

        func column(_ name: String) -> Int? {
            header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        // Only columns the data can't be built without are required.
        // Everything else is read if present.
        let requiredColumns = ["Type", "Date", "Vehicle", "Odometer", "Filled Up", "Gallons", "Total Cost"]
        guard
            let typeCol = column("Type"),
            let dateCol = column("Date"),
            let vehicleCol = column("Vehicle"),
            let odometerCol = column("Odometer"),
            let filledUpCol = column("Filled Up"),
            let gallonsCol = column("Gallons"),
            let totalCostCol = column("Total Cost")
        else {
            let missing = requiredColumns.filter { column($0) == nil }
            return .failed("This doesn't look like a Fuelly export. Missing column\(missing.count == 1 ? "" : "s"): \(missing.joined(separator: ", ")).")
        }
        let timeCol = column("Time")
        let pricePerGallonCol = column("Cost/Gallon")
        let octaneCol = column("Octane")
        let gasBrandCol = column("Gas Brand")
        let locationCol = column("Location")
        let paymentTypeCol = column("Payment Type")
        let notesCol = column("Notes")
        let servicesCol = column("Services")

        /// Safe cell access. A short row returns "" instead of crashing.
        func cell(_ row: [String], _ col: Int?) -> String {
            guard let col, col < row.count else { return "" }
            return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var fuelEntries: [ImportedFuelEntry] = []
        var maintenanceEntries: [ImportedMaintenanceEntry] = []
        var vehicleNames: [String] = []
        var skippedRows: [ImportSkippedRow] = []
        let dateParser = DateParser()

        func registerVehicle(_ name: String) {
            if !vehicleNames.contains(name) { vehicleNames.append(name) }
        }

        for (offset, row) in csv.rows.enumerated().dropFirst() {
            let rowNumber = offset + 1
            func skip(_ reason: String) {
                skippedRows.append(ImportSkippedRow(row: rowNumber, reason: reason))
            }

            // Fully blank lines aren't data. Ignore without reporting.
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }

            let vehicleName = cell(row, vehicleCol)
            guard !vehicleName.isEmpty else {
                skip("No vehicle name.")
                continue
            }

            // More fields than the header means an unquoted delimiter inside a
            // value (usually the notes) pushed later values into the wrong
            // columns. The row is kept, with a warning so it gets reviewed.
            let fieldCountWarning: String? = row.count > header.count
                ? "This row has \(row.count) fields but the header has \(header.count), so some values may be in the wrong columns."
                : nil

            let recordType = cell(row, typeCol)
            let isFuel = recordType.caseInsensitiveCompare("Gas") == .orderedSame
            let isService = recordType.caseInsensitiveCompare("Service") == .orderedSame
            guard isFuel || isService else {
                skip(recordType.isEmpty ? "No record type." : "Unrecognized record type “\(recordType)”.")
                continue
            }

            let rawDate = cell(row, dateCol)
            guard let date = dateParser.parse(date: rawDate, time: cell(row, timeCol)) else {
                skip(rawDate.isEmpty ? "No date." : "Couldn't read the date “\(rawDate)”.")
                continue
            }

            let rawOdometer = cell(row, odometerCol)
            let parsedMileage = parseOdometer(rawOdometer, decimalComma: decimalComma)
            let place = combinedStationName(brand: cell(row, gasBrandCol), location: cell(row, locationCol))
            let notes = cell(row, notesCol)

            // Same rule manual entry enforces (see Models.isFutureDate).
            var warnings: [String] = []
            if let fieldCountWarning {
                warnings.append(fieldCountWarning)
            }
            if isFutureDate(date) {
                warnings.append("Dated in the future.")
            }

            if isFuel {
                // MPG depends on the odometer, so a fuel-up without one
                // can't be imported as-is.
                guard let mileage = parsedMileage else {
                    skip(rawOdometer.isEmpty
                         ? "Fuel-up has no odometer reading."
                         : "Couldn't read the odometer reading “\(rawOdometer)”.")
                    continue
                }

                let rawGallons = cell(row, gallonsCol)
                guard case .value(let gallons) = parseNumber(rawGallons, decimalComma: decimalComma), gallons > 0 else {
                    skip(rawGallons.isEmpty
                         ? "Fuel-up has no gallons."
                         : "Couldn't use the gallons value “\(rawGallons)”.")
                    continue
                }

                let costs = resolveFuelCost(
                    gallons: gallons,
                    rawPrice: cell(row, pricePerGallonCol),
                    rawTotal: cell(row, totalCostCol),
                    decimalComma: decimalComma
                )
                warnings += costs.warnings

                let rawFilled = cell(row, filledUpCol)
                let isFullTank: Bool
                if let parsed = parseFullTank(rawFilled) {
                    isFullTank = parsed
                } else {
                    // Partial is the safe default: a mislabeled partial just
                    // merges two MPG intervals, while a mislabeled full
                    // creates a wrong one.
                    isFullTank = false
                    warnings.append(rawFilled.isEmpty
                        ? "Full/partial not recorded. Imported as partial so it can't distort MPG."
                        : "Couldn't tell whether “\(rawFilled)” means full or partial. Imported as partial so it can't distort MPG.")
                }

                let rawGrade = cell(row, octaneCol)
                let grade = parseFuelGrade(rawGrade)
                if grade == nil {
                    warnings.append("Unrecognized fuel grade “\(rawGrade)”. Imported as Regular.")
                }

                registerVehicle(vehicleName)
                fuelEntries.append(ImportedFuelEntry(
                    sourceRow: rowNumber,
                    vehicleName: vehicleName,
                    date: date,
                    mileage: mileage,
                    gallons: gallons,
                    pricePerGallon: costs.pricePerGallon,
                    totalCost: costs.totalCost,
                    isFullTank: isFullTank,
                    fuelGrade: grade ?? .regular,
                    stationName: place,
                    paymentMethod: parsePaymentMethod(cell(row, paymentTypeCol)),
                    notes: notes,
                    warnings: warnings
                ))
            } else {
                // Service records without an odometer are legitimate
                // (registration, a receipt with no mileage), so they're
                // imported with a warning instead of skipped.
                if parsedMileage == nil {
                    warnings.append(rawOdometer.isEmpty
                        ? "No odometer reading. Imported without mileage."
                        : "Couldn't read the odometer reading “\(rawOdometer)”. Imported without mileage.")
                }

                let rawCost = cell(row, totalCostCol)
                let cost: Double
                switch parseNumber(rawCost, decimalComma: decimalComma) {
                case .value(let value) where value >= 0:
                    cost = value
                case .empty:
                    cost = 0
                default:
                    cost = 0
                    warnings.append("Couldn't read the cost “\(rawCost)”. Imported as $0.")
                }

                // A service row with no description still carries a date
                // and cost, so it's imported rather than dropped.
                let services = cell(row, servicesCol)
                if services.isEmpty {
                    warnings.append("No service description in the file. Imported as “Service”.")
                }

                registerVehicle(vehicleName)
                maintenanceEntries.append(ImportedMaintenanceEntry(
                    sourceRow: rowNumber,
                    vehicleName: vehicleName,
                    date: date,
                    mileage: parsedMileage ?? 0,
                    cost: cost,
                    title: services.isEmpty ? "Service" : services,
                    type: services.isEmpty ? .other : inferMaintenanceType(from: services),
                    shopName: place,
                    notes: notes,
                    warnings: warnings
                ))
            }
        }

        if csv.endedInsideQuotes {
            skippedRows.append(ImportSkippedRow(
                row: csv.rows.count,
                reason: "Unmatched quotation mark. This row and anything after it were merged together and couldn't be read reliably."
            ))
        }

        if fuelEntries.isEmpty && maintenanceEntries.isEmpty {
            let detail = skippedRows.first.map { " First problem (row \($0.row)): \($0.reason)" } ?? ""
            return .failed("No fuel-ups or service records could be read from this file.\(detail)")
        }

        flagOdometerRegressions(fuel: &fuelEntries, maintenance: &maintenanceEntries)
        markInFileDuplicates(&fuelEntries)
        markInFileDuplicates(&maintenanceEntries)

        return ImportResult(
            fuelEntries: fuelEntries,
            maintenanceEntries: maintenanceEntries,
            vehicleNames: vehicleNames,
            skippedRows: skippedRows,
            fileError: nil
        )
    }

    // MARK: Review against destination vehicles

    /// Checks parsed entries against the existing vehicles they're about
    /// to be imported into. It uses the same rules manual entry uses
    /// (`mileageConflict`, `isBeforeManufactureYear`) plus a duplicate check
    /// against records already saved, which catches a file imported twice.
    ///
    /// Call this whenever the vehicle mapping changes. It's safe to call
    /// repeatedly. Pass only names mapped to existing vehicles; entries
    /// headed for a brand-new vehicle are left as-is.
    static func review(_ result: ImportResult, destinations: [String: Vehicle]) -> ImportResult {
        var reviewed = result

        for i in reviewed.fuelEntries.indices {
            var entry = reviewed.fuelEntries[i]
            entry.vehicleWarnings = []
            if entry.duplicateReason == .alreadyOnVehicle { entry.duplicateReason = nil }
            if let vehicle = destinations[entry.vehicleName] {
                if entry.duplicateReason == nil,
                   vehicle.fuelLogs.contains(where: { entry.isSameEvent(as: $0) }) {
                    entry.duplicateReason = .alreadyOnVehicle
                }
                entry.vehicleWarnings = vehicleWarnings(date: entry.date, mileage: entry.mileage, vehicle: vehicle)
            }
            reviewed.fuelEntries[i] = entry
        }

        for i in reviewed.maintenanceEntries.indices {
            var entry = reviewed.maintenanceEntries[i]
            entry.vehicleWarnings = []
            if entry.duplicateReason == .alreadyOnVehicle { entry.duplicateReason = nil }
            if let vehicle = destinations[entry.vehicleName] {
                if entry.duplicateReason == nil,
                   vehicle.maintenanceRecords.contains(where: { entry.isSameEvent(as: $0) }) {
                    entry.duplicateReason = .alreadyOnVehicle
                }
                entry.vehicleWarnings = vehicleWarnings(date: entry.date, mileage: entry.mileage, vehicle: vehicle)
            }
            reviewed.maintenanceEntries[i] = entry
        }

        return reviewed
    }

    private static func vehicleWarnings(date: Date, mileage: Int, vehicle: Vehicle) -> [String] {
        var warnings: [String] = []
        if isBeforeManufactureYear(date, vehicleYear: vehicle.year) {
            warnings.append("Dated before this vehicle's model year (\(vehicle.year)).")
        }
        if mileage > 0, let conflict = vehicle.mileageConflict(forDate: date, mileage: mileage) {
            let when = conflict.date.formatted(date: .abbreviated, time: .omitted)
            warnings.append("Odometer doesn't line up with an existing entry on \(when) at \(conflict.mileage.formatted()) mi.")
        }
        return warnings
    }

    // MARK: Vehicle creation helpers

    /// Best guess at model year for a vehicle being created from the import.
    /// Uses a leading year in the Fuelly name ("2019 4Runner TRD") if there
    /// is one. Otherwise it uses the year of that vehicle's earliest entry,
    /// never the current year, which would make every imported entry fail
    /// the before-manufacture check the first time it's edited.
    static func suggestedModelYear(forVehicle name: String, in result: ImportResult) -> Int {
        if let year = leadingYear(in: name) { return year }
        let dates = result.fuelEntries.filter { $0.vehicleName == name }.map(\.date)
            + result.maintenanceEntries.filter { $0.vehicleName == name }.map(\.date)
        return Calendar.current.component(.year, from: dates.min() ?? .now)
    }

    /// A 4-digit year at the start of a vehicle name, if present.
    static func leadingYear(in name: String) -> Int? {
        guard let first = name.split(separator: " ").first,
              first.count == 4,
              let year = Int(first),
              (1900..<2100).contains(year)
        else { return nil }
        return year
    }

    // MARK: Data checks

    /// Within the file, per vehicle: flags any entry whose odometer is
    /// lower than an entry from an earlier day. This is the same idea as
    /// `Vehicle.mileageConflict`, applied before anything is saved.
    private static func flagOdometerRegressions(
        fuel: inout [ImportedFuelEntry],
        maintenance: inout [ImportedMaintenanceEntry]
    ) {
        enum Kind { case fuel, maintenance }
        struct Ref {
            let kind: Kind
            let index: Int
            let vehicle: String
            let date: Date
            let mileage: Int
        }

        let fuelRefs = fuel.indices.map {
            Ref(kind: .fuel, index: $0, vehicle: fuel[$0].vehicleName, date: fuel[$0].date, mileage: fuel[$0].mileage)
        }
        let maintenanceRefs = maintenance.indices
            .filter { maintenance[$0].mileage > 0 }
            .map {
                Ref(kind: .maintenance, index: $0, vehicle: maintenance[$0].vehicleName, date: maintenance[$0].date, mileage: maintenance[$0].mileage)
            }

        let calendar = Calendar.current
        for group in Dictionary(grouping: fuelRefs + maintenanceRefs, by: \.vehicle).values {
            let ordered = group.sorted { ($0.date, $0.mileage) < ($1.date, $1.mileage) }
            var highest: Ref?
            for ref in ordered {
                if let highest, ref.mileage < highest.mileage, !calendar.isDate(ref.date, inSameDayAs: highest.date) {
                    let when = highest.date.formatted(date: .abbreviated, time: .omitted)
                    let message = "Odometer (\(ref.mileage.formatted()) mi) is lower than an earlier entry on \(when) (\(highest.mileage.formatted()) mi). One of the two readings is likely a typo."
                    switch ref.kind {
                    case .fuel: fuel[ref.index].warnings.append(message)
                    case .maintenance: maintenance[ref.index].warnings.append(message)
                    }
                }
                if ref.mileage > (highest?.mileage ?? 0) {
                    highest = ref
                }
            }
        }
    }

    /// Flags later copies of an event. The first occurrence is always kept,
    /// and each row is compared only against rows that are themselves
    /// being kept, so a chain of near-matches can't knock out a real entry.
    private static func markInFileDuplicates<Entry: ImportDuplicateCheckable>(_ entries: inout [Entry]) {
        // Grouped by vehicle so entries are only compared where a match is possible.
        var indicesByVehicle: [String: [Int]] = [:]
        for i in entries.indices {
            indicesByVehicle[entries[i].vehicleName, default: []].append(i)
        }
        for indices in indicesByVehicle.values {
            for position in indices.indices where position > 0 {
                let i = indices[position]
                for j in indices[..<position] where entries[j].duplicateReason == nil {
                    if entries[i].isSameEvent(as: entries[j]) {
                        entries[i].duplicateReason = .earlierRowInFile(row: entries[j].sourceRow)
                        break
                    }
                }
            }
        }
    }

    // MARK: Field parsing

    private enum NumberField {
        case empty
        case invalid
        case value(Double)
    }

    /// Turns a number as written in the file into one `Double` can read.
    /// - Standard files: "$1,234.56" → "1234.56" (commas are thousands).
    /// - Decimal-comma files: "1.234,56" → "1234.56" and "12,5" → "12.5".
    ///   A "." is only treated as a thousands separator when a "," is also
    ///   present, so "12.345" gallons stays 12.345.
    /// Currency symbols and space-style group separators are removed either way.
    private static func normalizedNumberText(_ raw: String, decimalComma: Bool) -> String {
        let ignored: Set<Character> = ["$", "€", "£", " ", "\u{00A0}", "\u{202F}", "'"]
        var text = String(raw.filter { !ignored.contains($0) })
        if decimalComma {
            if text.contains(",") {
                text = text.replacingOccurrences(of: ".", with: "")
                text = text.replacingOccurrences(of: ",", with: ".")
            }
        } else {
            text = text.replacingOccurrences(of: ",", with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Distinguishes a blank field from one that has text but isn't a
    /// number, so callers can warn on the second case instead of silently
    /// storing 0.
    private static func parseNumber(_ raw: String, decimalComma: Bool) -> NumberField {
        let cleaned = normalizedNumberText(raw, decimalComma: decimalComma)
        guard !cleaned.isEmpty else { return .empty }
        guard let value = Double(cleaned), value.isFinite else { return .invalid }
        return .value(value)
    }

    /// Keeps the decimal point so "45123.4" is 45,123 rather than 451,234.
    /// Strips thousands separators and unit text ("45,123 mi"). Returns nil
    /// for missing, zero, or absurd readings.
    private static func parseOdometer(_ raw: String, decimalComma: Bool) -> Int? {
        let numeric = raw.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }
        let cleaned = normalizedNumberText(numeric, decimalComma: decimalComma)
        guard let value = Double(cleaned), value.isFinite, value > 0, value < 10_000_000 else { return nil }
        return Int(value.rounded())
    }

    /// Fills in whichever of price and total is missing, the same way the
    /// manual fuel form falls back to gallons × price. Warns when the file's
    /// numbers disagree.
    private static func resolveFuelCost(
        gallons: Double,
        rawPrice: String,
        rawTotal: String,
        decimalComma: Bool
    ) -> (pricePerGallon: Double, totalCost: Double, warnings: [String]) {
        var warnings: [String] = []

        func read(_ raw: String, label: String) -> Double? {
            switch parseNumber(raw, decimalComma: decimalComma) {
            case .value(let value) where value >= 0:
                return value
            case .empty:
                return nil
            default:
                warnings.append("Couldn't read the \(label) “\(raw)”.")
                return nil
            }
        }

        let price = read(rawPrice, label: "price per gallon")
        let total = read(rawTotal, label: "total cost")

        switch (price, total) {
        case let (p?, t?):
            let expected = gallons * p
            if abs(expected - t) > max(0.50, t * 0.05) {
                warnings.append("Total cost (\(currency(t))) doesn't match gallons × price (\(currency(expected))).")
            }
            return (p, t, warnings)
        case let (p?, nil):
            let computed = (gallons * p * 100).rounded() / 100
            warnings.append("No total cost in the file. Calculated as \(currency(computed)) from gallons × price.")
            return (p, computed, warnings)
        case let (nil, t?):
            return ((t / gallons * 1000).rounded() / 1000, t, warnings)
        case (nil, nil):
            warnings.append("No cost information. Imported as $0.")
            return (0, 0, warnings)
        }
    }

    private static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: AppCurrency.code))
    }

    /// nil means the value wasn't recognized. The caller decides the
    /// default and attaches a warning.
    private static func parseFullTank(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "full", "yes", "y", "true", "1": return true
        case "partial", "no", "n", "false", "0", "not full": return false
        default: return nil
        }
    }

    /// nil means the value had text but wasn't recognized. Blank is
    /// treated as Regular without a warning, since it's common in exports.
    private static func parseFuelGrade(_ raw: String) -> FuelGrade? {
        let lower = raw.lowercased()
        if lower.isEmpty { return .regular }
        if lower.contains("diesel") { return .diesel }
        if lower.contains("e85") || lower.contains("flex") { return .e85 }
        if lower.contains("premium") || lower.contains("super") { return .premium }
        if lower.contains("mid") || lower.contains("plus") { return .midGrade }
        // "Low [Octane: 85]" is common in high-altitude states.
        if lower.contains("regular") || lower.contains("low") || lower.contains("unleaded") { return .regular }

        let octane = lower
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
            .first { (80...100).contains($0) }
        guard let octane else { return nil }
        if octane >= 91 { return .premium }
        if octane >= 88 { return .midGrade }
        return .regular
    }

    /// Unknown or blank values map to .other rather than assuming a credit
    /// card, so payment-method reports don't overstate credit card use.
    private static func parsePaymentMethod(_ raw: String) -> FuelPaymentMethod {
        let lower = raw.lowercased()
        if lower.isEmpty { return .other }
        if lower.contains("cash") { return .cash }
        if lower.contains("debit") { return .debitCard }
        if lower.contains("business") || lower.contains("fleet") || lower.contains("company") { return .businessCard }
        let creditTerms = ["credit", "visa", "mastercard", "master card", "amex", "american express", "discover"]
        if creditTerms.contains(where: { lower.contains($0) }) { return .creditCard }
        return .other
    }

    /// Matches whole words and phrases, not substrings, so "ignition coil"
    /// is no longer an Oil Change and "tire pressure check" is no longer a
    /// Tire Replacement. Checks run from most specific to least; the first
    /// match wins, and oil change keeps priority on combined rows like
    /// "Oil change, tire rotation".
    private static func inferMaintenanceType(from servicesText: String) -> MaintenanceType {
        let words = servicesText.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }
        func hasAny(_ phrases: [String]) -> Bool { phrases.contains(where: has) }

        if hasAny(["chain lube", "chain lubrication", "lube chain", "chain lubed"]) { return .chainLubrication }
        if hasAny(["chain adjustment", "chain adjust", "adjust chain", "chain tension", "chain slack"]) { return .chainAdjustment }
        if hasAny(["valve clearance", "valve adjustment", "valve adjust", "valve check"]) { return .valveClearance }
        if hasAny(["coolant flush", "coolant exchange", "coolant change", "radiator flush"]) { return .coolantFlush }

        let oilRepairWords = ["leak", "pan", "pressure", "sensor", "gasket", "pump", "cooler", "seal"]
        if hasAny(["oil change", "oil and filter", "oil filter", "oil service"])
            || (has("oil") && !hasAny(oilRepairWords)) {
            return .oilChange
        }

        if hasAny(["tire rotation", "tires rotated", "rotate tires", "rotation"]) { return .tireRotation }

        let tireServiceWords = ["pressure", "patch", "plug", "repair", "balance", "balancing", "alignment", "check"]
        if hasAny(["tire", "tires"]) && !hasAny(tireServiceWords) { return .tireReplacement }

        if hasAny(["brake", "brakes", "pads", "rotors"]) { return .brakes }
        if has("battery") { return .battery }
        if hasAny(["air filter", "cabin filter"]) { return .airFilter }
        if hasAny(["registration", "license plate", "plates", "tag", "tags"]) { return .registration }
        if hasAny(["inspection", "inspect", "inspected", "emissions", "smog", "safety check"]) { return .inspection }
        if hasAny(["fluid", "fluids", "coolant", "antifreeze", "power steering", "differential"]) { return .fluids }
        return .other
    }

    private static func combinedStationName(brand: String, location: String) -> String {
        let brand = brand.trimmingCharacters(in: .whitespaces)
        let location = location.trimmingCharacters(in: .whitespaces)
        // Skip anything that's just a stray number, seen in some Fuelly
        // exports as a data-entry glitch in the Gas Brand field.
        let cleanBrand = brand.allSatisfy(\.isNumber) ? "" : brand
        if !cleanBrand.isEmpty && !location.isEmpty && cleanBrand != location {
            return "\(cleanBrand) — \(location)"
        }
        return cleanBrand.isEmpty ? location : cleanBrand
    }

    // MARK: Dates

    /// Created once per parse rather than once per row. Returns nil instead
    /// of substituting today's date.
    private struct DateParser {
        private let withTime: [DateFormatter]
        private let dateOnly: DateFormatter

        init() {
            func make(_ format: String) -> DateFormatter {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                return formatter
            }
            withTime = [make("yyyy-MM-dd h:mm a"), make("yyyy-MM-dd HH:mm"), make("yyyy-MM-dd HH:mm:ss")]
            dateOnly = make("yyyy-MM-dd")
        }

        func parse(date: String, time: String) -> Date? {
            let date = date.trimmingCharacters(in: .whitespaces)
            guard !date.isEmpty else { return nil }
            let time = time.trimmingCharacters(in: .whitespaces)
            if !time.isEmpty {
                for formatter in withTime {
                    if let parsed = formatter.date(from: "\(date) \(time)") { return parsed }
                }
            }
            // Time is cosmetic. If it can't be read, the date alone is fine.
            return dateOnly.date(from: date)
        }
    }

    // MARK: CSV

    private struct CSVParseOutput {
        var rows: [[String]]
        var endedInsideQuotes: Bool
    }

    /// Picks the field separator by counting commas, semicolons, and tabs
    /// in the header line (outside quotes) and using the most common one.
    static func detectDelimiter(_ text: String) -> Unicode.Scalar {
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var insideQuotes = false
        for scalar in text.unicodeScalars {
            if scalar == "\"" { insideQuotes.toggle(); continue }
            if insideQuotes { continue }
            if scalar == "\n" || scalar == "\r" { break }
            if counts[scalar] != nil { counts[scalar, default: 0] += 1 }
        }
        let best = counts.max { $0.value < $1.value }
        guard let best, best.value > 0 else { return "," }
        return best.key
    }

    /// Handles quoted fields containing the delimiter (e.g. "FWB, FL"),
    /// escaped quotes (""), and LF, CR, or CRLF line endings.
    ///
    /// - A quote only starts a quoted field at the very beginning of the
    ///   field. A quote anywhere else is kept as a literal character, so a
    ///   note like `Installed 2" leveling kit` no longer swallows the rest of
    ///   the file.
    /// - Works on Unicode scalars (4 bytes each) rather than an array of
    ///   Characters (about 16 bytes each), which cuts memory use for large
    ///   files by roughly three-quarters.
    private static func parseCSVRows(_ text: String, delimiter: Unicode.Scalar) -> CSVParseOutput {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = String.UnicodeScalarView()
        var insideQuotes = false

        func endField() {
            currentRow.append(String(currentField))
            currentField = String.UnicodeScalarView()
        }
        func endRow() {
            endField()
            if !(currentRow.count == 1 && currentRow[0].isEmpty) {
                rows.append(currentRow)
            }
            currentRow = []
        }

        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if insideQuotes {
                if scalar == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(scalar)
                }
            } else if scalar == "\"" && currentField.isEmpty {
                insideQuotes = true
            } else if scalar == delimiter {
                endField()
            } else if scalar == "\r" || scalar == "\n" {
                if scalar == "\r" && i + 1 < scalars.count && scalars[i + 1] == "\n" {
                    i += 1
                }
                endRow()
            } else {
                currentField.append(scalar)
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            endRow()
        }
        return CSVParseOutput(rows: rows, endedInsideQuotes: insideQuotes)
    }
}
