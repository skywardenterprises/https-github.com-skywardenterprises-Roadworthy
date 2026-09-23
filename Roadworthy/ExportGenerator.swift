import UIKit
import CoreText
import ImageIO

/// Builds the PDF files behind the Export & Share feature. CSV files are
/// built by CSVGenerator.
enum ExportGenerator {
    private static let pageWidth: CGFloat = 612    // US Letter, 72 dpi
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 40
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }
    private static var contentBottom: CGFloat { pageHeight - margin }

    /// Receipt photos are shown at most 180 points tall, so about 800 pixels
    /// on the long edge is plenty. Embedding originals made large reports
    /// hundreds of megabytes and could run the app out of memory.
    private static let receiptMaxPixel: CGFloat = 800

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

    /// Everything a continuation page needs to redraw its header. Passed
    /// through every section so no section falls back to a default unit.
    private struct PageContext {
        let ctx: UIGraphicsPDFRendererContext
        let title: String
        let vehicle: Vehicle
        let unit: DistanceUnit
    }

    // MARK: - Public entry points

    static func maintenanceHistoryPDF(vehicle: Vehicle, unit: DistanceUnit) -> Data {
        render { ctx in
            let page = PageContext(ctx: ctx, title: "Maintenance History", vehicle: vehicle, unit: unit)
            var cursor: CGFloat = 0
            beginPage(page, cursor: &cursor)
            drawMaintenanceSection(page, cursor: &cursor, includeSectionHeader: false)
        }
    }

    static func fullVehicleHistoryPDF(vehicle: Vehicle, unit: DistanceUnit) -> Data {
        render { ctx in
            let page = PageContext(ctx: ctx, title: "Vehicle History Report", vehicle: vehicle, unit: unit)
            var cursor: CGFloat = 0
            beginPage(page, cursor: &cursor)

            drawVehicleInfoSection(page, cursor: &cursor)
            drawMaintenanceSection(page, cursor: &cursor, includeSectionHeader: true)
            drawFuelSection(page, cursor: &cursor)
            drawExpenseSection(page, cursor: &cursor)
            drawReminderSection(page, cursor: &cursor)
            drawSpecsSection(page, cursor: &cursor)
        }
    }

    /// - Parameter taxYear: Only trips dated in this calendar year are
    ///   included, since the IRS rate and the deduction are per tax year.
    ///   Pass nil for every trip (the estimated deduction is then omitted,
    ///   because one rate can't apply across years).
    static func businessMileageLogPDF(vehicle: Vehicle, rate: Double, unit: DistanceUnit, taxYear: Int?) -> Data {
        let title = taxYear.map { "Business Mileage Log — \($0)" } ?? "Business Mileage Log — All Years"
        return render { ctx in
            let page = PageContext(ctx: ctx, title: title, vehicle: vehicle, unit: unit)
            var cursor: CGFloat = 0
            beginPage(page, cursor: &cursor)
            drawBusinessMileageSection(page, rate: rate, taxYear: taxYear, cursor: &cursor)
        }
    }

    /// The tax years that have at least one trip, newest first. ExportView
    /// uses this for its year picker.
    static func tripYears(for vehicle: Vehicle) -> [Int] {
        let years = Set(vehicle.trips.map { Calendar.current.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    private static func render(_ body: (UIGraphicsPDFRendererContext) -> Void) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { ctx in body(ctx) }
    }

    // MARK: - Page / header helpers

    private static func beginPage(_ page: PageContext, cursor: inout CGFloat) {
        page.ctx.beginPage()
        cursor = margin
        draw(text: "\(page.vehicle.displayName) — \(page.title)", attributes: titleAttributes, cursor: &cursor)
        cursor += 4
        draw(text: subtitleLine(page.vehicle, unit: page.unit), attributes: subtitleAttributes, cursor: &cursor)
        cursor += 4
        draw(text: "Generated \(Date.now.formatted(date: .abbreviated, time: .shortened))", attributes: subtitleAttributes, cursor: &cursor)
        cursor += 12
        drawDivider(cursor: cursor)
        cursor += 12
    }

    private static func subtitleLine(_ vehicle: Vehicle, unit: DistanceUnit) -> String {
        var parts = ["\(vehicle.year) \(vehicle.make) \(vehicle.model)", formattedDistance(vehicle.currentMileage, unit: unit)]
        if !vehicle.vin.isEmpty { parts.append("VIN: \(vehicle.vin)") }
        if !vehicle.licensePlate.isEmpty { parts.append("Plate: \(vehicle.licensePlate)") }
        return parts.joined(separator: "  •  ")
    }

    private static func ensureSpace(_ page: PageContext, needed: CGFloat, cursor: inout CGFloat) {
        if cursor + needed > contentBottom {
            beginPage(page, cursor: &cursor)
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

    // MARK: - Text drawing

    private static func height(of attributed: NSAttributedString) -> CGFloat {
        let size = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
        return ceil(attributed.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil).height)
    }

    /// Draws text at the cursor with no page handling. Only for short,
    /// fixed text (headers, one-line summaries) placed after `ensureSpace`.
    @discardableResult
    private static func draw(text: String, attributes: [NSAttributedString.Key: Any], cursor: inout CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textHeight = height(of: attributed)
        attributed.draw(
            with: CGRect(x: margin, y: cursor, width: contentWidth, height: textHeight),
            options: .usesLineFragmentOrigin,
            context: nil
        )
        cursor += textHeight
        return textHeight
    }

    /// Draws text of any length, continuing onto new pages as needed.
    /// Previously a long note that started near the bottom of a page was
    /// drawn past the margin and cut off, and a note taller than a page
    /// lost its middle. Core Text works out how many whole lines fit in
    /// the space left on each page.
    private static func drawFlowing(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        page: PageContext,
        cursor: inout CGFloat
    ) {
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let fullHeight = height(of: attributed)

        // Common case: it fits where we are.
        if cursor + fullHeight <= contentBottom {
            draw(attributed, cursor: &cursor)
            return
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let length = attributed.length
        var location = 0
        // True right after starting a page for this text. If not even one
        // line fits on a brand-new page, the rest is drawn as-is and the loop
        // ends, so it can never start pages forever.
        var onFreshPage = false
        while location < length {
            let available = contentBottom - cursor
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: contentWidth, height: max(available, 0)), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)

            if visible.length == 0 {
                if onFreshPage {
                    let rest = attributed.attributedSubstring(from: NSRange(location: location, length: length - location))
                    draw(rest, cursor: &cursor)
                    return
                }
                beginPage(page, cursor: &cursor)
                onFreshPage = true
                continue
            }

            let piece = attributed.attributedSubstring(from: NSRange(location: visible.location, length: visible.length))
            draw(piece, cursor: &cursor)
            location += visible.length
            onFreshPage = false
            if location < length {
                beginPage(page, cursor: &cursor)
                onFreshPage = true
            }
        }
    }

    private static func draw(_ attributed: NSAttributedString, cursor: inout CGFloat) {
        let textHeight = height(of: attributed)
        attributed.draw(
            with: CGRect(x: margin, y: cursor, width: contentWidth, height: textHeight),
            options: .usesLineFragmentOrigin,
            context: nil
        )
        cursor += textHeight
    }

    // MARK: - Receipt photo embedding

    /// Decodes a photo straight to a small thumbnail with ImageIO, without
    /// ever holding the full-size bitmap in memory.
    private static func downsampledImage(_ data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: receiptMaxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Draws a receipt photo inline, scaled to fit the page width with a
    /// capped height so one large photo can't dominate the whole report.
    /// Reserves space first so the image never gets cut across a page break.
    private static func drawReceiptPhotoIfPresent(_ data: Data?, page: PageContext, cursor: inout CGFloat) {
        guard let data, let image = downsampledImage(data), image.size.height > 0 else { return }
        let maxHeight: CGFloat = 180
        let aspectRatio = image.size.width / image.size.height
        var width = contentWidth
        var height = width / aspectRatio
        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        ensureSpace(page, needed: height + 12, cursor: &cursor)
        image.draw(in: CGRect(x: margin, y: cursor, width: width, height: height))
        cursor += height + 8
    }

    // MARK: - Section: Vehicle Info

    private static func drawVehicleInfoSection(_ page: PageContext, cursor: inout CGFloat) {
        let vehicle = page.vehicle
        draw(text: "Vehicle Information", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let info = [
            "Year/Make/Model: \(vehicle.year) \(vehicle.make) \(vehicle.model)",
            "Nickname: \(vehicle.nickname.isEmpty ? "—" : vehicle.nickname)",
            "Odometer: \(formattedDistance(vehicle.currentMileage, unit: page.unit))",
            "VIN: \(vehicle.vin.isEmpty ? "—" : vehicle.vin)",
            "Plate: \(vehicle.licensePlate.isEmpty ? "—" : vehicle.licensePlate)",
            "Purchased: \(vehicle.purchaseDate.formatted(date: .abbreviated, time: .omitted))"
        ]
        for line in info {
            drawFlowing(line, attributes: bodyAttributes, page: page, cursor: &cursor)
            cursor += 2
        }
        cursor += 12
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Maintenance

    private static func drawMaintenanceSection(_ page: PageContext, cursor: inout CGFloat, includeSectionHeader: Bool) {
        if includeSectionHeader {
            ensureSpace(page, needed: 40, cursor: &cursor)
            draw(text: "Maintenance History", attributes: sectionHeaderAttributes, cursor: &cursor)
            cursor += 6
        }
        let records = page.vehicle.maintenanceRecords.sorted { $0.date > $1.date }
        if records.isEmpty {
            draw(text: "No maintenance logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for record in records {
            // Releases each record's temporary objects (decoded photo, text
            // layout) before moving on, instead of holding every record's
            // until the whole report is done.
            autoreleasepool {
                ensureSpace(page, needed: 40, cursor: &cursor)
                drawFlowing(record.title, attributes: headingAttributes, page: page, cursor: &cursor)
                let line = "\(record.date.formatted(date: .abbreviated, time: .omitted))  •  \(formattedDistance(record.mileage, unit: page.unit))  •  \(record.cost.formatted(.currency(code: AppCurrency.code)))"
                drawFlowing(line, attributes: secondaryAttributes, page: page, cursor: &cursor)
                if !record.notes.isEmpty {
                    drawFlowing(record.notes, attributes: bodyAttributes, page: page, cursor: &cursor)
                }
                drawReceiptPhotoIfPresent(record.receiptPhotoData, page: page, cursor: &cursor)
                cursor += 8
            }
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Fuel

    private static func drawFuelSection(_ page: PageContext, cursor: inout CGFloat) {
        ensureSpace(page, needed: 40, cursor: &cursor)
        draw(text: "Fuel Log", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let logs = page.vehicle.fuelLogs.sorted { $0.date > $1.date }
        if logs.isEmpty {
            draw(text: "No fuel logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for log in logs {
            autoreleasepool {
                ensureSpace(page, needed: 30, cursor: &cursor)
                let gallonsText = log.gallons.formatted(.number.precision(.fractionLength(1)))
                let line = "\(log.date.formatted(date: .abbreviated, time: .omitted))  •  \(formattedDistance(log.mileage, unit: page.unit))  •  \(gallonsText) gal @ \(log.pricePerGallon.formatted(.currency(code: AppCurrency.code)))  •  \(log.totalCost.formatted(.currency(code: AppCurrency.code)))"
                drawFlowing(line, attributes: bodyAttributes, page: page, cursor: &cursor)
                if !log.notes.isEmpty {
                    drawFlowing(log.notes, attributes: secondaryAttributes, page: page, cursor: &cursor)
                }
                drawReceiptPhotoIfPresent(log.receiptPhotoData, page: page, cursor: &cursor)
                cursor += 2
            }
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Expenses

    private static func drawExpenseSection(_ page: PageContext, cursor: inout CGFloat) {
        ensureSpace(page, needed: 40, cursor: &cursor)
        draw(text: "Other Expenses", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let expenses = page.vehicle.expenses.sorted { $0.date > $1.date }
        if expenses.isEmpty {
            draw(text: "No expenses logged.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for expense in expenses {
            autoreleasepool {
                ensureSpace(page, needed: 30, cursor: &cursor)
                let line = "\(expense.date.formatted(date: .abbreviated, time: .omitted))  •  \(expense.category.rawValue)  •  \(expense.amount.formatted(.currency(code: AppCurrency.code)))"
                drawFlowing(line, attributes: bodyAttributes, page: page, cursor: &cursor)
                if !expense.notes.isEmpty {
                    drawFlowing(expense.notes, attributes: secondaryAttributes, page: page, cursor: &cursor)
                }
                drawReceiptPhotoIfPresent(expense.receiptPhotoData, page: page, cursor: &cursor)
                cursor += 4
            }
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Reminders

    private static func drawReminderSection(_ page: PageContext, cursor: inout CGFloat) {
        ensureSpace(page, needed: 40, cursor: &cursor)
        draw(text: "Recurring Reminders", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let reminders = page.vehicle.reminders
        if reminders.isEmpty {
            draw(text: "No reminders set.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for reminder in reminders {
            ensureSpace(page, needed: 30, cursor: &cursor)
            drawFlowing(reminder.title, attributes: headingAttributes, page: page, cursor: &cursor)
            var details: [String] = []
            if let nextDueMileage = reminder.nextDueMileage {
                details.append("Every \(convertFromMiles(reminder.intervalMiles, to: page.unit).formatted()) \(page.unit.rawValue) — next at \(formattedDistance(nextDueMileage, unit: page.unit))")
            }
            if let nextDueDate = reminder.nextDueDate {
                details.append("Every \(reminder.intervalMonths) mo — next on \(nextDueDate.formatted(date: .abbreviated, time: .omitted))")
            }
            if !details.isEmpty {
                drawFlowing(details.joined(separator: "  •  "), attributes: secondaryAttributes, page: page, cursor: &cursor)
            }
            cursor += 4
        }
        cursor += 8
        drawDivider(cursor: cursor)
        cursor += 12
    }

    // MARK: - Section: Vehicle Specs

    private static func drawSpecsSection(_ page: PageContext, cursor: inout CGFloat) {
        ensureSpace(page, needed: 40, cursor: &cursor)
        draw(text: "Vehicle Specs", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        let specs = page.vehicle.specs
        if specs.isEmpty {
            draw(text: "No specs saved.", attributes: secondaryAttributes, cursor: &cursor)
        }
        for spec in specs.sorted(by: { $0.name < $1.name }) {
            ensureSpace(page, needed: 20, cursor: &cursor)
            var line = "\(spec.category.rawValue): \(spec.name)"
            if !spec.value.isEmpty { line += " — \(spec.value)" }
            if !spec.brand.isEmpty { line += " (\(spec.brand))" }
            drawFlowing(line, attributes: bodyAttributes, page: page, cursor: &cursor)
            if !spec.notes.isEmpty {
                drawFlowing(spec.notes, attributes: secondaryAttributes, page: page, cursor: &cursor)
            }
            cursor += 2
        }
    }

    // MARK: - Section: Business Mileage

    private static func drawBusinessMileageSection(_ page: PageContext, rate: Double, taxYear: Int?, cursor: inout CGFloat) {
        let calendar = Calendar.current
        let trips = page.vehicle.trips
            .filter { trip in taxYear.map { calendar.component(.year, from: trip.date) == $0 } ?? true }
            .sorted { $0.date < $1.date }
        let businessMiles = trips.filter { $0.purpose == .business }.reduce(0) { $0 + $1.milesDriven }

        draw(text: "Summary", attributes: sectionHeaderAttributes, cursor: &cursor)
        cursor += 6
        draw(text: "Total Business Distance: \(formattedDistance(businessMiles, unit: page.unit))", attributes: bodyAttributes, cursor: &cursor)
        cursor += 2
        if let taxYear {
            // The deduction is always figured in actual statute miles — the
            // IRS rate is defined per mile regardless of the person's display
            // unit preference — but everything shown on the page respects it.
            let deduction = Double(businessMiles) * rate
            draw(text: "Rate per Mile: $" + String(format: "%.3f", rate), attributes: bodyAttributes, cursor: &cursor)
            cursor += 2
            draw(text: "Estimated \(taxYear) Deduction: " + deduction.formatted(.currency(code: AppCurrency.code)), attributes: bodyAttributes, cursor: &cursor)
            cursor += 2
            draw(text: "Uses the rate set in Roadworthy. Confirm it matches the IRS standard mileage rate for \(taxYear), which can change mid-year.", attributes: secondaryAttributes, cursor: &cursor)
        } else {
            draw(text: "No deduction estimate: this log covers more than one tax year, and the IRS rate differs by year. Export a single year for an estimate.", attributes: secondaryAttributes, cursor: &cursor)
        }
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
            ensureSpace(page, needed: 40, cursor: &cursor)
            let heading = "\(trip.date.formatted(date: .abbreviated, time: .omitted)) — \(trip.purpose.rawValue) — \(formattedDistance(trip.milesDriven, unit: page.unit))"
            drawFlowing(heading, attributes: headingAttributes, page: page, cursor: &cursor)

            var detailParts: [String] = ["\(convertFromMiles(trip.startMileage, to: page.unit).formatted()) → \(convertFromMiles(trip.endMileage, to: page.unit).formatted()) \(page.unit.rawValue)"]
            if !trip.fromLocation.isEmpty || !trip.toLocation.isEmpty {
                detailParts.append("\(trip.fromLocation) → \(trip.toLocation)")
            }
            drawFlowing(detailParts.joined(separator: "  •  "), attributes: secondaryAttributes, page: page, cursor: &cursor)

            if trip.purpose == .business && !trip.businessPurposeNote.isEmpty {
                drawFlowing(trip.businessPurposeNote, attributes: bodyAttributes, page: page, cursor: &cursor)
            }
            cursor += 8
        }
    }
}
