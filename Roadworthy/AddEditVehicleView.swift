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
    @State private var currentMileage = 0
    @State private var purchaseDate = Date.now
    @State private var photoData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    private var isEditing: Bool { vehicle != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
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
                    .onChange(of: selectedPhoto) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                photoData = data
                            }
                        }
                    }
                }

                Section("Vehicle Info") {
                    TextField("Nickname (e.g. My Truck)", text: $nickname)
                    TextField("Make (e.g. Toyota)", text: $make)
                    TextField("Model (e.g. Tacoma)", text: $model)
                    Stepper("Year: \(year)", value: $year, in: 1950...2100)
                }

                Section("Details") {
                    TextField("VIN", text: $vin)
                    TextField("License Plate", text: $licensePlate)
                    HStack {
                        Text("Current Mileage")
                        Spacer()
                        TextField("Mileage", value: $currentMileage, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }
            }
            .navigationTitle(isEditing ? "Edit Vehicle" : "Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
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
        currentMileage = vehicle.currentMileage
        purchaseDate = vehicle.purchaseDate
        photoData = vehicle.photoData
    }

    private func save() {
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
                photoData: photoData
            )
            context.insert(newVehicle)
        }
        dismiss()
    }
}
