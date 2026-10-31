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
                title: L("Date Is In the Future"),
                message: L("This entry is dated %@, which hasn't happened yet. Choose today's date or an earlier one.", shown)
            )
        }
        if isBeforeVehicleExisted(date, vehicleYear: vehicle.year) {
            return EntryProblem(
                title: L("Date Is Before This Vehicle Existed"),
                message: L("This entry is dated %@, but a %lld model went on sale in %lld at the earliest. Check the date, or the vehicle's year in Edit Vehicle.", shown, vehicle.year, vehicle.year - 1)
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
            title: L("Odometer Doesn't Add Up"),
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
                title: L("Odometer Doesn't Add Up"),
                message: L("The start odometer is lower than a reading from %@ (%@). Check the start reading or the trip date.", earlier.date.formatted(date: .abbreviated, time: .omitted), formattedDistance(earlier.mileage, unit: unit))
            )
        }
        if let later = valid
            .filter({ calendar.startOfDay(for: $0.date) > tripDay && $0.mileage < end })
            .min(by: { $0.mileage < $1.mileage }) {
            return EntryProblem(
                title: L("Odometer Doesn't Add Up"),
                message: L("The end odometer is higher than a later reading from %@ (%@). Check the end reading or the trip date.", later.date.formatted(date: .abbreviated, time: .omitted), formattedDistance(later.mileage, unit: unit))
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
            Text(LocalizedStringKey(label))
            Spacer()
            TextField(LocalizedStringKey(placeholder), text: $text)
                .numericKeyboard(.numberPad)
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

// MARK: - Date entry

/// A date row that shows the chosen date and, when tapped, opens spinning
/// month, day and year wheels right under it. Tap the row again to close
/// them. This replaces the small pop-up calendar, which was easy to
/// misread; the wheels show the whole date at once and follow the device's
/// date order (month, day, year in the U.S.).
struct WheelDatePicker: View {
    let title: LocalizedStringKey
    @Binding var date: Date
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(isOpen ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Repeat interval entry

/// A "repeat every X" entry that is obvious to use: a boxed number field
/// that looks tappable, a +/- stepper, and one-tap common choices. Used for
/// the mileage and month intervals on reminders.
struct IntervalField: View {
    let label: LocalizedStringKey
    let unit: Text
    @Binding var text: String
    var maxDigits: Int
    /// How much each tap of the stepper adds or removes.
    var step: Int = 1
    /// Common choices shown as buttons: the number and the text on its button.
    let quickPicks: [(value: Int, label: String)]

    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool

    private var current: Int { DigitsField.value(of: text, maxDigits: maxDigits) ?? 0 }
    private var maxValue: Int { Int(pow(10.0, Double(maxDigits))) - 1 }

    private func set(_ value: Int) {
        let clamped = min(max(value, 0), maxValue)
        text = clamped == 0 ? "" : DigitsField.formatted(String(clamped), maxDigits: maxDigits, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(label)
                Spacer()
                TextField("0", text: $text)
                    .numericKeyboard(.numberPad)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .frame(minWidth: 84)
                    .fixedSize()
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .onChange(of: text) { _, newValue in
                        let formatted = DigitsField.formatted(newValue, maxDigits: maxDigits, locale: locale)
                        if formatted != newValue { text = formatted }
                    }
                unit.foregroundStyle(.secondary)
                Stepper("", onIncrement: { set(current + step) }, onDecrement: { set(current - step) })
                    .labelsHidden()
            }
            Text("Common choices")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPicks, id: \.value) { pick in
                        Button {
                            set(pick.value)
                        } label: {
                            Text(pick.label)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(current == pick.value ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(current == pick.value ? Color.white : Color.primary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
            .foregroundStyle(.red)
    }
}

extension View {
    /// Blocks swipe-to-dismiss while there are unsaved changes, and shows a
    /// "Discard changes?" prompt. Set `isConfirming` from the Cancel button
    /// when `hasChanges` is true.
    func discardChangesGuard(hasChanges: Bool, isConfirming: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        self
            .interactiveDismissDisabled(hasChanges)
            // An alert, not a confirmation dialog: on iPad a dialog is a popover
            // that hides its cancel button, so "Keep Editing" never showed.
            .alert("Discard your changes?", isPresented: isConfirming) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard Changes", role: .destructive, action: onDiscard)
            }
    }

    /// Confirmation before a single delete from inside an edit form.
    func deleteConfirmation(_ title: String, isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Confirmation for swipe-to-delete in a list. The rows being deleted are
    /// captured at swipe time, so a sync change while the dialog is open
    /// can't shift which rows get deleted.
    func confirmDeletion<Item>(of pending: Binding<[Item]>, noun: String, perform: @escaping ([Item]) -> Void) -> some View {
        let count = pending.wrappedValue.count
        let title = count == 1
            ? AppLocalization.string("Delete this \(noun)?")
            : L("Delete %lld " + noun + "s?", count)
        return alert(
            Text(verbatim: title),
            isPresented: Binding(
                get: { !pending.wrappedValue.isEmpty },
                set: { if !$0 { pending.wrappedValue = [] } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                let items = pending.wrappedValue
                pending.wrappedValue = []
                perform(items)
            }
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

    /// Larger size used while a photo is being cropped and rotated, so the
    /// final crop of a small area (a receipt in a wide photo) stays sharp.
    static let workingLongEdge: CGFloat = 3000
    static let workingJPEGQuality: CGFloat = 0.9

    static func jpegData(
        from image: UIImage,
        maxLongEdge: CGFloat = ImageNormalizer.maxLongEdge,
        quality: CGFloat = ImageNormalizer.jpegQuality
    ) -> Data? {
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
        return resized.jpegData(compressionQuality: quality)
    }

    /// Upright, high-quality copy for the crop and rotate screen.
    static func workingData(from image: UIImage) -> Data? {
        jpegData(from: image, maxLongEdge: workingLongEdge, quality: workingJPEGQuality)
    }

    static func workingData(from data: Data) -> Data? {
        UIImage(data: data).flatMap { workingData(from: $0) }
    }

    static func normalize(_ data: Data) -> Data? {
        UIImage(data: data).flatMap { jpegData(from: $0) }
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

private struct PendingPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

/// Loads a photo chosen in a PhotosPicker, then lets the person rotate and
/// crop it before it is attached (see PhotoCropRotateView).
/// Shows an alert if the photo can't be loaded (for example an iCloud Photos
/// original that hasn't downloaded while offline), instead of silently
/// attaching nothing.
private struct PickedPhotoLoader: ViewModifier {
    @Binding var item: PhotosPickerItem?
    @Binding var data: Data?
    @Binding var isLoading: Bool
    @State private var showingFailure = false
    @State private var pendingPhoto: PendingPhoto?

    func body(content: Content) -> some View {
        content
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                isLoading = true
                Task { @MainActor in
                    let raw = try? await newItem.loadTransferable(type: Data.self)
                    let working = await Task.detached(priority: .userInitiated) {
                        raw.flatMap { ImageNormalizer.workingData(from: $0) }
                    }.value
                    if let working {
                        // The photo is only attached after it has been
                        // rotated and cropped (or accepted as is).
                        pendingPhoto = PendingPhoto(data: working)
                    } else {
                        showingFailure = true
                    }
                    // Cleared so the same photo can be chosen again later.
                    item = nil
                    isLoading = false
                }
            }
            .fullScreenCover(item: $pendingPhoto) { pending in
                PhotoCropRotateView(
                    workingData: pending.data,
                    onDone: { cropped in
                        data = cropped
                        pendingPhoto = nil
                    },
                    onCancel: { pendingPhoto = nil }
                )
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
            return L("Your change couldn't be saved (code %lld). Please try again. If this keeps happening, contact %@.", nsError.code, SupportConfig.email)
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
