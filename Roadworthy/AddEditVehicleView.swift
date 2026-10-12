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
    @State private var engineSizeText = ""
    @State private var engineSizeUnit: EngineSizeUnit = .liters
    @State private var trim = ""
    @State private var bodyStyle = ""
    @State private var cylindersText = ""
    @State private var fuelType = ""
    @State private var driveType = ""
    @State private var transmission = ""
    @State private var showingVINPrompt = false
    @State private var vinNote: String?

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
            return L("Enter a make and model to save.")
        }
        if let vehicle, enteredMileage < vehicle.highestLoggedMileage {
            return L("Current odometer can't be lower than the highest logged reading (%@).", formattedDistance(vehicle.highestLoggedMileage, unit: distanceUnit))
        }
        if isLoadingPhoto {
            return L("Waiting for the photo to finish loading…")
        }
        return nil
    }

    /// Normalized values (parsed numbers, uppercased IDs) so formatting that
    /// happens on load doesn't count as an edit.
    private var draft: [AnyHashable] {
        formSnapshot(
            nickname, make, model, year, vin.uppercased(), licensePlate.uppercased(),
            DigitsField.value(of: mileageText), purchaseDate, photoData, isActive, vehicleType,
            Double(purchasePriceText), Double(currentValueText),
            parsedEngineSize, engineSizeUnit.rawValue,
            trim.trimmed, bodyStyle.trimmed, parsedCylinders, fuelType.trimmed, driveType.trimmed, transmission.trimmed
        )
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    /// Accepts "5.7" or "5,7". Nil when empty or not a positive number.
    private var parsedEngineSize: Double? {
        let cleaned = engineSizeText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedCylinders: Int? {
        guard let value = Int(cylindersText), value > 0 else { return nil }
        return value
    }

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
                            Text(LocalizedStringKey(photoData == nil ? "Add Photo" : "Change Photo"))
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
                            Group {
                                if let asset = type.customIconAsset {
                                    Label(LocalizedStringKey(type.rawValue), image: asset)
                                } else {
                                    Label(LocalizedStringKey(type.rawValue), systemImage: type.iconName)
                                }
                            }
                            .tag(type)
                        }
                    }
                    TextField("Nickname (e.g. My Truck)", text: $nickname)
                    TextField("Make (e.g. Toyota)", text: $make)
                    TextField("Model (e.g. Tacoma)", text: $model)
                    HStack {
                        Text("Engine Size")
                        Spacer()
                        TextField("Optional", text: $engineSizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: engineSizeText) { _, newValue in
                                let filtered = String(newValue.filter { $0.isNumber || $0 == "." || $0 == "," }.prefix(7))
                                if filtered != newValue { engineSizeText = filtered }
                            }
                        Picker("Engine Size Unit", selection: $engineSizeUnit) {
                            ForEach(EngineSizeUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
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
                    Button {
                        showingVINPrompt = true
                    } label: {
                        Label("Look Up VIN", systemImage: "magnifyingglass")
                    }
                    if let vinNote {
                        Text(vinNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField("License Plate", text: $licensePlate)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onChange(of: licensePlate) { _, newValue in
                            licensePlate = newValue.uppercased()
                        }
                    DigitsField(
                        label: "Current Odometer (\(distanceUnit.rawValue))",
                        placeholder: "Odometer",
                        text: $mileageText
                    )
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }

                Section("Additional Details") {
                    optionalTextRow("Trim", text: $trim)
                    optionalTextRow("Body Style", text: $bodyStyle)
                    LabeledContent("Cylinders") {
                        TextField("Optional", text: $cylindersText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: cylindersText) { _, newValue in
                                let filtered = String(newValue.filter(\.isNumber).prefix(2))
                                if filtered != newValue { cylindersText = filtered }
                            }
                    }
                    optionalTextRow("Fuel Type", text: $fuelType)
                    optionalTextRow("Transmission", text: $transmission)
                    optionalTextRow("Drive Type", text: $driveType)
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
            .navigationTitle(LocalizedStringKey(isEditing ? "Edit Vehicle" : "Add Vehicle"))
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
            .sheet(isPresented: $showingVINPrompt) {
                VINPromptView(
                    initialVIN: vin,
                    skipTitle: isEditing ? "Cancel" : "Skip, I'll Enter It Myself",
                    onSkip: isEditing ? nil : { skippedVIN in keepSkippedVIN(skippedVIN) },
                    onDecoded: { decodedVIN, result in
                        applyVIN(decodedVIN, result)
                        showingVINPrompt = false
                    }
                )
            }
            .saveErrorAlert($saveError)
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
        }
    }

    private func optionalTextRow(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("Optional", text: text)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Keeps a VIN that was scanned or typed but not looked up (for example
    /// with no internet), so Look Up VIN can be tapped later.
    private func keepSkippedVIN(_ skippedVIN: String) {
        guard !skippedVIN.isEmpty else { return }
        vin = skippedVIN
        vinNote = L("The VIN was kept. Tap Look Up VIN when you're back online.")
    }

    /// Copies what the VIN lookup returned into the form. Nothing is saved
    /// until the person taps Save, and blank results never erase typed values.
    private func applyVIN(_ decodedVIN: String, _ result: VINDecodeResult) {
        vin = decodedVIN
        if let decodedYear = result.year { year = decodedYear }
        if !result.make.isEmpty { make = result.make }
        if !result.model.isEmpty { model = result.model }
        if !result.trim.isEmpty { trim = result.trim }
        if !result.bodyStyle.isEmpty { bodyStyle = result.bodyStyle }
        if !result.fuelType.isEmpty { fuelType = result.fuelType }
        if !result.driveType.isEmpty { driveType = result.driveType }
        if !result.transmission.isEmpty { transmission = result.transmission }
        if let cylinders = result.cylinders { cylindersText = String(cylinders) }
        if let size = result.engineSize {
            engineSizeUnit = EngineSizeUnit(rawValue: result.engineUnitSymbol) ?? .liters
            engineSizeText = size.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        }
        switch result.kind {
        case .car: vehicleType = .car
        case .truck: vehicleType = .truck
        case .motorcycle: vehicleType = .motorcycle
        case .rv: vehicleType = .rv
        case nil: break
        }
        var note = L("Vehicle details were filled in from the VIN. Review them before saving.")
        if result.checkDigitMismatch {
            note += " " + L("The VIN's check digit didn't match, so double-check it for typos.")
        }
        vinNote = note
        Haptics.success()
    }

    private func loadExistingValues() {
        // onAppear can run again (for example after another sheet closes).
        // Loading twice would overwrite what the person has typed.
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let vehicle else {
            // New vehicle: offer the VIN lookup once the sheet has settled.
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                showingVINPrompt = true
            }
            return
        }
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
        trim = vehicle.trim
        bodyStyle = vehicle.bodyStyle
        cylindersText = vehicle.cylinders.map { String($0) } ?? ""
        fuelType = vehicle.fuelType
        driveType = vehicle.driveType
        transmission = vehicle.transmission
        engineSizeUnit = vehicle.engineSizeUnit
        engineSizeText = vehicle.engineSize.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
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
            if vehicle.currentMileage != currentMileage { vehicle.odometerUpdatedDate = .now }
            vehicle.currentMileage = currentMileage
            vehicle.purchaseDate = purchaseDate
            vehicle.photoData = photoData
            vehicle.vehicleType = vehicleType
            vehicle.purchasePrice = purchasePrice
            vehicle.engineSize = parsedEngineSize
            vehicle.engineSizeUnit = engineSizeUnit
            vehicle.trim = trim.trimmed
            vehicle.bodyStyle = bodyStyle.trimmed
            vehicle.cylinders = parsedCylinders
            vehicle.fuelType = fuelType.trimmed
            vehicle.driveType = driveType.trimmed
            vehicle.transmission = transmission.trimmed

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
            newVehicle.engineSize = parsedEngineSize
            newVehicle.engineSizeUnit = engineSizeUnit
            newVehicle.trim = trim.trimmed
            newVehicle.bodyStyle = bodyStyle.trimmed
            newVehicle.cylinders = parsedCylinders
            newVehicle.fuelType = fuelType.trimmed
            newVehicle.driveType = driveType.trimmed
            newVehicle.transmission = transmission.trimmed
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
