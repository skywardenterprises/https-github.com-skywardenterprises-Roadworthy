import SwiftUI
import SwiftData
import PhotosUI

struct AddEditVehicleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibraryPicker = false
    @State private var showingPhotoViewer = false
    @State private var isActive = true
    @State private var vehicleType: VehicleType = .car
    @State private var purchasePriceText = ""
    @State private var currentValueText = ""

    private var isEditing: Bool { vehicle != nil }

    // Current year first, going back to 1950 — e.g. 2026, 2025, 2024, ...
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array((1950...currentYear).reversed())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    Button {
                        showingPhotoOptions = true
                    } label: {
                        HStack {
                            if let photoData, let uiImage = UIImage(data: photoData) {
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
                    .confirmationDialog("Vehicle Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
                        Button("Take Photo") { showingCamera = true }
                        Button("Choose from Library") {
                            // The PhotosPicker below is triggered by binding a
                            // Bool to it, same pattern as the camera sheet.
                            showingPhotoLibraryPicker = true
                        }
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
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                photoData = data
                            }
                        }
                    }
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
                    HStack {
                        Text("Current Mileage")
                        Spacer()
                        TextField("Mileage", text: $mileageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: mileageText) { _, newValue in
                                let digitsOnly = newValue.filter(\.isNumber)
                                mileageText = digitsOnly.isEmpty ? "" : (Int(digitsOnly)?.formatted() ?? digitsOnly)
                            }
                    }
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }

                Section {
                    HStack {
                        Text("Purchase Price")
                        Spacer()
                        TextField("Price", text: $purchasePriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Est. Current Value")
                        Spacer()
                        TextField("Value", text: $currentValueText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(make.isEmpty || model.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
        }
    }

    private func loadExistingValues() {
        guard let vehicle else { return }
        nickname = vehicle.nickname
        make = vehicle.make
        model = vehicle.model
        year = vehicle.year
        vin = vehicle.vin
        licensePlate = vehicle.licensePlate
        mileageText = vehicle.currentMileage == 0 ? "" : vehicle.currentMileage.formatted()
        purchaseDate = vehicle.purchaseDate
        photoData = vehicle.photoData
        isActive = vehicle.isActive
        vehicleType = vehicle.vehicleType
        purchasePriceText = vehicle.purchasePrice == 0 ? "" : String(vehicle.purchasePrice)
        currentValueText = vehicle.estimatedCurrentValue.map { String($0) } ?? ""
    }

    private func save() {
        let currentMileage = Int(mileageText.filter(\.isNumber)) ?? 0
        let purchasePrice = Double(purchasePriceText) ?? 0
        let currentValue = currentValueText.isEmpty ? nil : Double(currentValueText)

        if let vehicle {
            vehicle.nickname = nickname
            vehicle.make = make
            vehicle.model = model
            vehicle.year = year
            vehicle.vin = vin
            vehicle.licensePlate = licensePlate
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
                nickname: nickname,
                make: make,
                model: model,
                year: year,
                vin: vin,
                licensePlate: licensePlate,
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
        Haptics.success()
        dismiss()
    }
}
