import SwiftUI
import SwiftData
import PhotosUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle

    private var sortedDocs: [VehicleDocument] {
        vehicle.documents.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        Group {
            if sortedDocs.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text",
                    description: Text("Use the + button to save photos of registration, insurance cards, receipts, etc.")
                )
            } else {
                List {
                    ForEach(sortedDocs) { doc in
                        NavigationLink {
                            DocumentDetailView(document: doc)
                        } label: {
                            HStack(spacing: 12) {
                                if let data = doc.imageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "doc.fill")
                                        .frame(width: 44, height: 44)
                                }
                                VStack(alignment: .leading) {
                                    Text(doc.title).font(.headline)
                                    Text(doc.dateAdded.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteDocs)
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteDocs(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedDocs[index])
        }
    }
}

struct DocumentDetailView: View {
    let document: VehicleDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let data = document.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if !document.notes.isEmpty {
                    Text(document.notes)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddDocumentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var title = ""
    @State private var notes = ""
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (e.g. Registration)", text: $title)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.title)
                        }
                        Text(imageData == nil ? "Add Photo" : "Change Photo")
                    }
                }
                .onChange(of: selectedPhoto) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            imageData = data
                        }
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() {
        let doc = VehicleDocument(title: title, imageData: imageData, notes: notes)
        doc.vehicle = vehicle
        context.insert(doc)
        dismiss()
    }
}
