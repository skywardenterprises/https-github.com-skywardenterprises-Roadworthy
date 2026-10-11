import SwiftUI
import SwiftData
import PhotosUI

struct AddEditVehicleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    // If editing an existing vehicle, pass it in. Nil means "creating new".
    var vehicle: Vehicle?

    @State private var nickname = ""
    @State private var make = ""
    @State private var model = ""
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var vin = ""
    @State private var licensePlate = ""
    @State private var mileageText = ""
    @State private var purchaseDate = Date.now
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibraryPicker = false
    @State private var showingPhotoViewer = false
    @State private var isActive = true
    @State private var vehicleType: VehicleType = .car
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""

    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []
    @State private var showingDiscardConfirm = false

    private var isEditing: Bool { vehicle != nil }

    /// Includes next calendar year, since model-year vehicles go on sale the
    /// year before. A stored year outside the range (for example from an
    /// import) is added so the picker never shows blank.
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        var years = Array((1950...(currentYear + 1)).reversed())
        if !years.contains(year) {
            years.append(year)
            years.sort(by: >)
        }
        return years
    }

    private var enteredMileage: Int {
        convertToMiles(DigitsField.value(of: mileageText) ?? 0, from: distanceUnit)
    }

    private var validationIssue: String? {
        if make.trimmed.isEmpty || model.trimmed.isEmpty {
            return "Enter a make and model to save."
        }
        if let vehicle, enteredMileage < vehicle.highestLoggedMileage {
            return "Current mileage can't be lower than the highest logged reading (\(formattedDistance(vehicle.highestLoggedMileage, unit: distanceUnit)))."
        }
        if isLoadingPhoto {
            return "Waiting for the photo to finish loading…"
        }
        return nil
    }

    /// Normalized values (parsed numbers, uppercased IDs) so formatting that
    /// happens on load doesn't count as an edit.
    private var draft: [AnyHashable] {
        formSnapshot(
            nickname, make, model, year, vin.uppercased(), licensePlate.uppercased(),
            DigitsField.value(of: mileageText), purchaseDate, photoData, isActive, vehicleType,
            Double(purchasePriceText), Double(currentValueText)
        )
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section("Photo") {
                    Button {
                        showingPhotoOptions = true
                    } label: {
                        HStack {
                            if isLoadingPhoto {
                                ProgressView()
                                    .frame(width: 60, height: 60)
                            } else if let photoData, let uiImage = ThumbnailCache.image(for: photoData, maxPixel: 180) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title)
                            }
                            Text(photoData == nil ? "Add Photo" : "Change Photo")
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(isLoadingPhoto)
                    .confirmationDialog("Vehicle Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
                        if CameraPicker.isAvailable {
                            Button("Take Photo") { showingCamera = true }
                        }
                        Button("Choose from Library") { showingPhotoLibraryPicker = true }
                        if photoData != nil {
                            Button("View Photo") { showingPhotoViewer = true }
                            Button("Remove Photo", role: .destructive) { photoData = nil }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .sheet(isPresented: $showingCamera) {
                        CameraPicker(imageData: $photoData)
                            .ignoresSafeArea()
                    }
                    .photosPicker(isPresented: $showingPhotoLibraryPicker, selection: $selectedPhoto, matching: .images)
                    .loadsPickedPhoto($selectedPhoto, into: $photoData, isLoading: $isLoadingPhoto)
                    .sheet(isPresented: $showingPhotoViewer) {
                        if let photoData, let uiImage = UIImage(data: photoData) {
                            NavigationStack {
                                ScrollView {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                }
                                .navigationTitle("Vehicle Photo")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingPhotoViewer = false }
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Vehicle Info") {
                    Picker("Vehicle Type", selection: $vehicleType) {
                        ForEach(VehicleType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }
                    TextField("Nickname (e.g. My Truck)", text: $nickname)
                    TextField("Make (e.g. Toyota)", text: $make)
                    TextField("Model (e.g. Tacoma)", text: $model)
                    Picker("Year", selection: $year) {
                        ForEach(availableYears, id: \.self) { y in
                            Text(String(y)).tag(y)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Details") {
                    TextField("VIN", text: $vin)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: vin) { _, newValue in
                            vin = newValue.uppercased()
                        }
                    TextField("License Plate", text: $licensePlate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: licensePlate) { _, newValue in
                            licensePlate = newValue.uppercased()
                        }
                    DigitsField(
                        label: "Current Mileage (\(distanceUnit.rawValue))",
                        placeholder: "Mileage",
                        text: $mileageText
                    )
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("Purchase Price")
                        Spacer()
                        AutoDecimalField(title: "Price", text: $purchasePriceText)
                    }
                    HStack {
                        Text("Est. Current Value")
                        Spacer()
                        AutoDecimalField(title: "Value", text: $currentValueText)
                    }
                } header: {
                    Text("Ownership Value")
                } footer: {
                    Text("Update the current value every so often (based on a quick KBB or Carvana check) to see an accurate cost-of-ownership calculation in Reports.")
                }

                if isEditing {
                    Section {
                        Toggle("Vehicle is Active", isOn: $isActive)
                    } footer: {
                        Text("Turn this off when you sell or retire this vehicle. It moves to the Inactive Vehicles list, but all of its history stays intact and can still be viewed.")
                    }
                }

                #if DEBUG
                if let vehicle {
                    Section {
                        Button("Generate Sample Data") {
                            SampleDataGenerator.generate(for: vehicle, context: context)
                            Haptics.success()
                        }
                    } footer: {
                        Text("DEBUG ONLY — adds about a year of realistic fuel, maintenance, expense, reminder, and trip data for testing. This button and its code don't exist in Release builds.")
                    }
                }
                #endif
            }
            .navigationTitle(isEditing ? "Edit Vehicle" : "Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(validationIssue != nil)
                }
            }
            .onAppear(perform: loadExistingValues)
            .saveErrorAlert($saveError)
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
        }
    }

    private func loadExistingValues() {
        // onAppear can run again (for example after another sheet closes).
        // Loading twice would overwrite what the person has typed.
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let vehicle else { return }
        nickname = vehicle.nickname
        make = vehicle.make
        model = vehicle.model
        year = vehicle.year
        vin = vehicle.vin
        licensePlate = vehicle.licensePlate
        mileageText = vehicle.currentMileage == 0 ? "" : String(convertFromMiles(vehicle.currentMileage, to: distanceUnit))
        purchaseDate = vehicle.purchaseDate
        photoData = vehicle.photoData
        isActive = vehicle.isActive
        vehicleType = vehicle.vehicleType
        purchasePriceText = vehicle.purchasePrice == 0 ? "" : String(vehicle.purchasePrice)
        currentValueText = vehicle.estimatedCurrentValue.map { String($0) } ?? ""
    }

    private func save() {
        guard validationIssue == nil else { return }
        let currentMileage = enteredMileage
        let purchasePrice = Double(purchasePriceText) ?? 0
        let currentValue = currentValueText.isEmpty ? nil : Double(currentValueText)

        if let vehicle {
            vehicle.nickname = nickname.trimmed
            vehicle.make = make.trimmed
            vehicle.model = model.trimmed
            vehicle.year = year
            vehicle.vin = vin.trimmed
            vehicle.licensePlate = licensePlate.trimmed
            vehicle.currentMileage = currentMileage
            vehicle.purchaseDate = purchaseDate
            vehicle.photoData = photoData
            vehicle.vehicleType = vehicleType
            vehicle.purchasePrice = purchasePrice

            if let currentValue {
                // Only refresh the "last updated" date if the value actually changed.
                if vehicle.estimatedCurrentValue != currentValue {
                    vehicle.estimatedValueUpdatedDate = .now
                }
                vehicle.estimatedCurrentValue = currentValue
            } else {
                vehicle.estimatedCurrentValue = nil
                vehicle.estimatedValueUpdatedDate = nil
            }

            let wasActive = vehicle.isActive
            vehicle.isActive = isActive
            if isActive {
                vehicle.inactiveDate = nil
            } else if wasActive {
                vehicle.inactiveDate = .now
            }
        } else {
            let newVehicle = Vehicle(
                nickname: nickname.trimmed,
                make: make.trimmed,
                model: model.trimmed,
                year: year,
                vin: vin.trimmed,
                licensePlate: licensePlate.trimmed,
                currentMileage: currentMileage,
                purchaseDate: purchaseDate,
                photoData: photoData,
                vehicleType: vehicleType,
                purchasePrice: purchasePrice,
                estimatedCurrentValue: currentValue,
                estimatedValueUpdatedDate: currentValue != nil ? .now : nil
            )
            context.insert(newVehicle)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }
}
