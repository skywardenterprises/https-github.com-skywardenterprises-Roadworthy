import UIKit

/// Builds the PDF and CSV files behind the Export & Share feature.
enum ExportGenerator {
    private static let pageWidth: CGFloat = 612    // US Letter, 72 dpi
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 40
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    private static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 18)
    ]
    private static let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11),
        .foregroundColor: UIColor.darkGray
    ]
    private static let sectionHeaderAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 14)
    ]
    private static let headingAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 12)
    ]
    private static let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11)
    ]
    private static let secondaryAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 10),
        .foregroundColor: UIColor.gray
    ]

    // MARK: - Public entry points

    static func maintenanceHistoryPDF(vehicle: Vehicle) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            var cursor: CGFloat = 0
            beginPage(ctx, title: "Maintenance History", vehicle: vehicle, cursor: &cursor)
            drawMaintenanceSection(ctx, vehicle: vehicle, pageTitle: "Maintenance History", cursor: &cursor, includeSectionHeader: false)
        }
    }

    static func fullVehicleHistoryPDF(vehicle: Vehicle) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            var cursor: CGFloat = 0
            beginPage(ctx, title: "Vehicle History Report", vehicle: vehicle, cursor: &cursor)

            drawVehicleInfoSection(vehicle: vehicle, cursor: &cursor)
            drawMaintenanceSection(ctx, vehicle: vehicle, pageTitle: "Vehicle History Report", cursor: &cursor, includeSectionHeader: true)
            drawFuelSection(ctx, vehicle: vehicle, pageTitle: "Vehicle History Report", cursor: &cursor)
            drawExpenseSection(ctx, vehicle: vehicle, pageTitle: "Vehicle History Report", cursor: &cursor)
            drawReminderSection(ctx, vehicle: vehicle, pageTitle: "Vehicle History Report", cursor: &cursor)
            drawSpecsSection(ctx, vehicle: vehicle, pageTitle: "Vehicle History Report", cursor: &cursor)
        }
    }

    static func businessMileageLogPDF(vehicle: Vehicle, rate: Double) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in
            var cursor: CGFloat = 0
            beginPage(ctx, title: "Business Mileage Log", vehicle: vehicle, cursor: &cursor)
            drawBusinessMileageSection(ctx, vehicle: vehicle, rate: rate, pageTitle: "Business Mileage Log", cursor: &cursor)
        }
    }

    // MARK: - Page / header helpers

    private static func beginPage(_ ctx: UIGraphicsPDFRendererContext, title: String, vehicle: Vehicle, cursor: inout CGFloat) {
        ctx.beginPage()
        cursor = margin
        draw(text: "\(vehicle.displayName) — \(title)", attributes: titleAttributes, cursor: &cursor)
        cursor += 4
        draw(text: subtitleLine(vehicle), attributes: subtitleAttributes, cursor: &cursor)
        cursor += 4
        draw(text: "Generated \(Date.now.formatted(date: .abbreviated, time: .shortened))", attributes: subtitleAttributes, cursor: &cursor)
        cursor += 12
        drawDivider(cursor: cursor)
        cursor += 12
    }

    private static func subtitleLine(_ vehicle: Vehicle) -> String {
        var parts = ["\(vehicle.year) \(vehicle.make) \(vehicle.model)", "\(vehicle.currentMileage.formatted()) mi"]
        if !vehicle.vin.isEmpty { parts.append("VIN: \(vehicle.vin)") }
        if !vehicle.licensePlate.isEmpty { parts.append("Plate: \(vehicle.licensePlate)") }
        return parts.joined(separator: "  •  ")
    }

    private static func ensureSpace(_ ctx: UIGraphicsPDFRendererContext, needed: CGFloat, pageTitle: String, vehicle: Vehicle, cursor: inout CGFloat) {
        if cursor + needed > pageHeight - margin {
            beginPage(ctx, title: pageTitle, vehicle: vehicle, cursor: &cursor)
        }
    }

    private static func drawDivider(cursor: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: cursor))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: cursor))
        UIColor.lightGray.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    // MARK: - Text drawing primitive

    @discardableResult
    private static func draw(text: String, attributes: [NSAttributedString.Key: Any], cursor: inout CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        let bounding = attributed.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
        let rect = CGRect(x: margin, y: cursor, width: contentWidth, height: bounding.height)
        attributed.draw(with: rect, options: .usesLineFragmentOrigin, context: nil)
        cursor += ceil(bounding.height)
        return bounding.height
    }

    // MARK: - Section: Vehicle Info

    private static func drawVehicleInfoSection(vehicle: Vehicle, cursor: inout CGFloat) {
        draw(text: "Vehicle Information", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let info = [
            "Year/Make/Model: \(vehicle.year) \(vehicle.make) \(vehicle.model)",
            "Nickname: \(vehicle.nickname.isEmpty ? "—" : vehicle.nickname)",
            "Mileage: \(vehicle.currentMileage.formatted()) mi",
            "VIN: \(vehicle.vin.isEmpty ? "—" : vehicle.vin)",
            "Plate: \(vehicle.licensePlate.isEmpty ? "—" : vehicle.licensePlate)",
            "Purchased: \(vehicle.purchaseDate.formatted(date: .abbreviated, time: .omitted))"
        ]
        for line in info {
            draw(text: line, attributes: bodyAttributes, cursor: &cursor)
            cursor += 2
        }
        cursor += 12
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Maintenance

    private static func drawMaintenanceSection(
        _ ctx: UIGraphicsPDFRendererContext,
        vehicle: Vehicle,
        pageTitle: String,
        cursor: inout CGFloat,
        includeSectionHeader: Bool
    ) {
        if includeSectionHeader {
            draw(text: "Maintenance History", attributes: sectionHeaderAttributes, cursor: &cursor)
            cursor += 6
        }
        let records = vehicle.maintenanceRecords.sorted { $0.date > $1.date }
        if records.isEmpty {
            draw(text: "No maintenance logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for record in records {
            ensureSpace(ctx, needed: 50, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            draw(text: record.title, attributes: headingAttributes, cursor: &cursor)
            let line = "\(record.date.formatted(date: .abbreviated, time: .omitted))  •  \(record.mileage.formatted()) mi  •  \(record.cost.formatted(.currency(code: "USD")))"
            draw(text: line, attributes: secondaryAttributes, cursor: &cursor)
            if !record.notes.isEmpty {
                draw(text: record.notes, attributes: bodyAttributes, cursor: &cursor)
            }
            cursor += 8
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Fuel

    private static func drawFuelSection(_ ctx: UIGraphicsPDFRendererContext, vehicle: Vehicle, pageTitle: String, cursor: inout CGFloat) {
        draw(text: "Fuel Log", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let logs = vehicle.fuelLogs.sorted { $0.date > $1.date }
        if logs.isEmpty {
            draw(text: "No fuel logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for log in logs {
            ensureSpace(ctx, needed: 30, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            let gallonsText = log.gallons.formatted(.number.precision(.fractionLength(1)))
            let line = "\(log.date.formatted(date: .abbreviated, time: .omitted))  •  \(log.mileage.formatted()) mi  •  \(gallonsText) gal @ \(log.pricePerGallon.formatted(.currency(code: "USD")))  •  \(log.totalCost.formatted(.currency(code: "USD")))"
            draw(text: line, attributes: bodyAttributes, cursor: &cursor)
            cursor += 2
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Expenses

    private static func drawExpenseSection(_ ctx: UIGraphicsPDFRendererContext, vehicle: Vehicle, pageTitle: String, cursor: inout CGFloat) {
        draw(text: "Other Expenses", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let expenses = vehicle.expenses.sorted { $0.date > $1.date }
        if expenses.isEmpty {
            draw(text: "No expenses logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for expense in expenses {
            ensureSpace(ctx, needed: 30, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            let line = "\(expense.date.formatted(date: .abbreviated, time: .omitted))  •  \(expense.category.rawValue)  •  \(expense.amount.formatted(.currency(code: "USD")))"
            draw(text: line, attributes: bodyAttributes, cursor: &cursor)
            if !expense.notes.isEmpty {
                draw(text: expense.notes, attributes: secondaryAttributes, cursor: &cursor)
            }
            cursor += 4
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Reminders

    private static func drawReminderSection(_ ctx: UIGraphicsPDFRendererContext, vehicle: Vehicle, pageTitle: String, cursor: inout CGFloat) {
        draw(text: "Recurring Reminders", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        if vehicle.reminders.isEmpty {
            draw(text: "No reminders set.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for reminder in vehicle.reminders {
            ensureSpace(ctx, needed: 30, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            draw(text: reminder.title, attributes: headingAttributes, cursor: &cursor)
            var details: [String] = []
            if let nextDueMileage = reminder.nextDueMileage {
                details.append("Every \(reminder.intervalMiles.formatted()) mi — next at \(nextDueMileage.formatted()) mi")
            }
            if let nextDueDate = reminder.nextDueDate {
                details.append("Every \(reminder.intervalMonths) mo — next on \(nextDueDate.formatted(date: .abbreviated, time: .omitted))")
            }
            if !details.isEmpty {
                draw(text: details.joined(separator: "  •  "), attributes: secondaryAttributes, cursor: &cursor)
            }
            cursor += 4
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Vehicle Specs

    private static func drawSpecsSection(_ ctx: UIGraphicsPDFRendererContext, vehicle: Vehicle, pageTitle: String, cursor: inout CGFloat) {
        draw(text: "Vehicle Specs", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        if vehicle.specs.isEmpty {
            draw(text: "No specs saved.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for spec in vehicle.specs.sorted(by: { $0.name < $1.name }) {
            ensureSpace(ctx, needed: 20, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            var line = "\(spec.category.rawValue): \(spec.name)"
            if !spec.value.isEmpty { line += " — \(spec.value)" }
            if !spec.brand.isEmpty { line += " (\(spec.brand))" }
            draw(text: line, attributes: bodyAttributes, cursor: &cursor)
            cursor += 2
        }
    }

    // MARK: - Section: Business Mileage

    private static func drawBusinessMileageSection(
        _ ctx: UIGraphicsPDFRendererContext,
        vehicle: Vehicle,
        rate: Double,
        pageTitle: String,
        cursor: inout CGFloat
    ) {
        let trips = vehicle.trips.sorted { $0.date < $1.date }
        let businessMiles = trips.filter { $0.purpose == .business }.reduce(0) { $0 + $1.milesDriven }
        let deduction = Double(businessMiles) * rate

        draw(text: "Summary", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        draw(text: "Total Business Miles: \(businessMiles.formatted())", attributes: bodyAttributes, cursor: &cursor)
        cursor += 2
        draw(text: "Rate per Mile: $" + String(format: "%.3f", rate), attributes: bodyAttributes, cursor: &cursor)
        cursor += 2
        draw(text: "Estimated Deduction: " + deduction.formatted(.currency(code: "USD")), attributes: bodyAttributes, cursor: &cursor)
        cursor += 12
        drawDivider(cursor: cursor)
        cursor += 12

        draw(text: "Trip Log", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6

        if trips.isEmpty {
            draw(text: "No trips logged.", attributes: secondaryAttributes, cursor: &cursor)
            return
        }

        for trip in trips {
            ensureSpace(ctx, needed: 50, pageTitle: pageTitle, vehicle: vehicle, cursor: &cursor)
            let heading = "\(trip.date.formatted(date: .abbreviated, time: .omitted)) — \(trip.purpose.rawValue) — \(trip.milesDriven.formatted()) mi"
            draw(text: heading, attributes: headingAttributes, cursor: &cursor)

            var detailParts: [String] = ["\(trip.startMileage.formatted()) → \(trip.endMileage.formatted()) mi"]
            if !trip.fromLocation.isEmpty || !trip.toLocation.isEmpty {
                detailParts.append("\(trip.fromLocation) → \(trip.toLocation)")
            }
            draw(text: detailParts.joined(separator: "  •  "), attributes: secondaryAttributes, cursor: &cursor)

            if trip.purpose == .business && !trip.businessPurposeNote.isEmpty {
                draw(text: trip.businessPurposeNote, attributes: bodyAttributes, cursor: &cursor)
            }
            cursor += 8
        }
    }
}
