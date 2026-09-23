import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import ImageIO

// MARK: - Text helpers

extension String {
    /// Leading and trailing whitespace removed. Used for every "required"
    /// check so a field containing only spaces doesn't count as filled in.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Entry validation shared by every dated form

/// A problem that blocks saving, shown as an alert with a title and message.
struct EntryProblem {
    let title: String
    let message: String
}

/// One set of date and odometer rules for fuel, maintenance, expense, and
/// trip forms, so each form checks the same things the same way.
enum EntryValidation {
    /// Model-year vehicles go on sale the calendar year before their model
    /// year, so a 2027 model can have entries dated 2026.
    static func isBeforeVehicleExisted(_ date: Date, vehicleYear: Int) -> Bool {
        // Delegates to the one implementation in Models.swift (also used by
        // the Fuelly importer), so the two can't drift apart.
        isBeforeManufactureYear(date, vehicleYear: vehicleYear)
    }

    static func dateProblem(_ date: Date, vehicle: Vehicle) -> EntryProblem? {
        let shown = date.formatted(date: .abbreviated, time: .omitted)
        if isFutureDate(date) {
            return EntryProblem(
                title: "Date Is In the Future",
                message: "This entry is dated \(shown), which hasn't happened yet. Choose today's date or an earlier one."
            )
        }
        if isBeforeVehicleExisted(date, vehicleYear: vehicle.year) {
            return EntryProblem(
                title: "Date Is Before This Vehicle Existed",
                message: "This entry is dated \(shown), but a \(vehicle.year) model went on sale in \(vehicle.year - 1) at the earliest. Check the date, or the vehicle's year in Edit Vehicle."
            )
        }
        return nil
    }

    /// Checks one odometer reading against logged fuel and maintenance
    /// entries. A reading of 0 (not recorded) is never treated as a conflict.
    static func mileageProblem(
        date: Date,
        mileage: Int,
        vehicle: Vehicle,
        excludingFuelLog: FuelLog? = nil,
        excludingMaintenanceRecord: MaintenanceRecord? = nil
    ) -> EntryProblem? {
        guard mileage > 0,
              let conflict = vehicle.mileageConflict(
                forDate: date,
                mileage: mileage,
                excludingFuelLog: excludingFuelLog,
                excludingMaintenanceRecord: excludingMaintenanceRecord
              )
        else { return nil }
        return EntryProblem(
            title: "Mileage Doesn't Add Up",
            message: buildMileageConflictMessage(newMileage: mileage, newDate: date, conflict: conflict)
        )
    }

    /// Trip readings checked against fuel and maintenance logs on other days
    /// only. A fuel stop in the middle of a trip is normal, so same-day
    /// entries are never treated as conflicts.
    static func tripProblem(date: Date, start: Int, end: Int, vehicle: Vehicle, unit: DistanceUnit) -> EntryProblem? {
        let calendar = Calendar.current
        let tripDay = calendar.startOfDay(for: date)
        let readings: [(date: Date, mileage: Int)] =
            vehicle.fuelLogs.map { ($0.date, $0.mileage) } + vehicle.maintenanceRecords.map { ($0.date, $0.mileage) }
        let valid = readings.filter { $0.mileage > 0 }

        if let earlier = valid
            .filter({ calendar.startOfDay(for: $0.date) < tripDay && $0.mileage > start })
            .max(by: { $0.mileage < $1.mileage }) {
            return EntryProblem(
                title: "Mileage Doesn't Add Up",
                message: "The start odometer is lower than a reading from \(earlier.date.formatted(date: .abbreviated, time: .omitted)) (\(formattedDistance(earlier.mileage, unit: unit))). Check the start reading or the trip date."
            )
        }
        if let later = valid
            .filter({ calendar.startOfDay(for: $0.date) > tripDay && $0.mileage < end })
            .min(by: { $0.mileage < $1.mileage }) {
            return EntryProblem(
                title: "Mileage Doesn't Add Up",
                message: "The end odometer is higher than a later reading from \(later.date.formatted(date: .abbreviated, time: .omitted)) (\(formattedDistance(later.mileage, unit: unit))). Check the end reading or the trip date."
            )
        }
        return nil
    }
}

extension Vehicle {
    /// The highest odometer reading in any fuel log, maintenance record, or
    /// trip. Current mileage should never be set below this.
    var highestLoggedMileage: Int {
        max(
            fuelLogs.map(\.mileage).max() ?? 0,
            maintenanceRecords.map(\.mileage).max() ?? 0,
            trips.map(\.endMileage).max() ?? 0
        )
    }
}

// MARK: - Whole-number field (odometer, intervals)

/// A whole-number field that shows grouping separators as the person types.
/// It replaces the odometer field that was copied into six forms, and fixes
/// two problems in that copy:
/// - A length cap, so a pasted long number can't overflow `Int` and save as 0.
/// - Formatting that follows the in-app language instead of the device
///   language. Digits in any script are read correctly.
struct DigitsField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var maxDigits: Int = 7
    var suffix: String? = nil

    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) { _, newValue in
                    let formatted = Self.formatted(newValue, maxDigits: maxDigits, locale: locale)
                    if formatted != newValue { text = formatted }
                }
            if let suffix {
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }

    static func formatted(_ raw: String, maxDigits: Int, locale: Locale) -> String {
        guard let value = value(of: raw, maxDigits: maxDigits) else { return "" }
        return value.formatted(.number.locale(locale))
    }

    /// The whole number in a field's text, or nil if it's empty.
    static func value(of text: String, maxDigits: Int = 9) -> Int? {
        let digits = text.compactMap(\.wholeNumberValue).prefix(maxDigits)
        guard !digits.isEmpty else { return nil }
        return digits.reduce(0) { $0 * 10 + $1 }
    }
}

// MARK: - Unsaved-change tracking

/// A comparable snapshot of a form's values. Each form takes one after
/// loading and compares against it to know whether anything changed.
/// Variadic so each value is converted on its own, which keeps the type
/// checker fast compared with one large mixed-type array literal.
func formSnapshot(_ values: AnyHashable...) -> [AnyHashable] { values }

// MARK: - Form messaging

/// Shown at the top of a form while Save is disabled, so the person knows
/// what's missing instead of facing a grayed-out button with no explanation.
struct FormIssueRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Blocks swipe-to-dismiss while there are unsaved changes, and shows a
    /// "Discard changes?" prompt. Set `isConfirming` from the Cancel button
    /// when `hasChanges` is true.
    func discardChangesGuard(hasChanges: Bool, isConfirming: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        self
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard your changes?", isPresented: isConfirming, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive, action: onDiscard)
                Button("Keep Editing", role: .cancel) {}
            }
    }

    /// Confirmation before a single delete from inside an edit form.
    func deleteConfirmation(_ title: String, isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Confirmation for swipe-to-delete in a list. The rows being deleted are
    /// captured at swipe time, so a sync change while the dialog is open
    /// can't shift which rows get deleted.
    func confirmDeletion<Item>(of pending: Binding<[Item]>, noun: String, perform: @escaping ([Item]) -> Void) -> some View {
        let count = pending.wrappedValue.count
        return confirmationDialog(
            count == 1 ? "Delete this \(noun)?" : "Delete \(count) \(noun)s?",
            isPresented: Binding(
                get: { !pending.wrappedValue.isEmpty },
                set: { if !$0 { pending.wrappedValue = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let items = pending.wrappedValue
                pending.wrappedValue = []
                perform(items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

// MARK: - Photos

/// One size and quality for every saved photo, whether it came from the
/// camera or the library. Library photos were previously saved at full
/// original size (often several MB each), which weighs on iCloud storage
/// and sync time.
// `nonisolated` so the resize can run off the main actor (the project uses
// main-actor default isolation, as DistanceUnit.swift's annotations show).
nonisolated enum ImageNormalizer {
    static let maxLongEdge: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.7

    static func jpegData(from image: UIImage) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxLongEdge / longEdge)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Drawing applies the photo's orientation, so the result is upright.
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    static func normalize(_ data: Data) -> Data? {
        UIImage(data: data).flatMap(jpegData(from:))
    }

    /// Decodes a photo straight to a small image with ImageIO, without ever
    /// holding the full-size bitmap in memory.
    static func thumbnail(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Small, cached versions of photos for rows and headers. Decoding a
/// full-size photo on every redraw caused stutter while scrolling; this
/// decodes each photo once at the size it's shown and reuses the result.
/// Full-screen viewers still decode the original so receipts stay readable.
enum ThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        return cache
    }()

    /// `maxPixel` is the long edge in pixels. Roughly 3× the point size on
    /// screen keeps it sharp on every current iPhone.
    static func image(for data: Data, maxPixel: CGFloat) -> UIImage? {
        // Size plus a hash of the first and last bytes identifies a photo
        // cheaply, without hashing the whole file on every redraw.
        let key = "\(data.count)-\(data.prefix(64).hashValue)-\(data.suffix(64).hashValue)-\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = ImageNormalizer.thumbnail(from: data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Loads a photo chosen in a PhotosPicker, normalized to the standard size.
/// Shows an alert if the photo can't be loaded (for example an iCloud Photos
/// original that hasn't downloaded while offline), instead of silently
/// attaching nothing.
private struct PickedPhotoLoader: ViewModifier {
    @Binding var item: PhotosPickerItem?
    @Binding var data: Data?
    @Binding var isLoading: Bool
    @State private var showingFailure = false

    func body(content: Content) -> some View {
        content
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                isLoading = true
                Task { @MainActor in
                    let raw = try? await newItem.loadTransferable(type: Data.self)
                    let normalized = await Task.detached(priority: .userInitiated) {
                        raw.flatMap(ImageNormalizer.normalize)
                    }.value
                    if let normalized {
                        data = normalized
                    } else {
                        showingFailure = true
                    }
                    // Cleared so the same photo can be chosen again later.
                    item = nil
                    isLoading = false
                }
            }
            .alert("Couldn't Load Photo", isPresented: $showingFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That photo couldn't be loaded. If it's stored in iCloud Photos, check your internet connection and try again.")
            }
    }
}

extension View {
    /// Loads a photo chosen in a PhotosPicker into `data`, normalized to the
    /// standard size. It sets `isLoading` while working so the form can
    /// disable Save, clears the selection afterward so the same photo can be
    /// chosen again after being removed, and shows an alert if loading fails.
    func loadsPickedPhoto(
        _ item: Binding<PhotosPickerItem?>,
        into data: Binding<Data?>,
        isLoading: Binding<Bool>
    ) -> some View {
        modifier(PickedPhotoLoader(item: item, data: data, isLoading: isLoading))
    }
}

// MARK: - Saving

extension ModelContext {
    /// Saves immediately instead of waiting for autosave. Returns a message to
    /// show if the save fails; the unsaved changes are rolled back so what's
    /// on screen matches what's stored. Every form save and every delete goes
    /// through this, so a failed save is never silent.
    func saveReportingErrors() -> String? {
        do {
            try save()
            return nil
        } catch {
            rollback()
            let nsError = error as NSError
            return "Your change couldn't be saved (code \(nsError.code)). Please try again. If this keeps happening, contact \(SupportConfig.email)."
        }
    }
}

extension View {
    /// Shows a save failure from `saveReportingErrors()`.
    func saveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Couldn't Save",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
