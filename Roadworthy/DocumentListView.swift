import SwiftUI
import SwiftData
import PhotosUI

struct DocumentListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var pendingDeletion: [VehicleDocument] = []
    @State private var saveError: String?

    private var sortedDocs: [VehicleDocument] {
        vehicle.documents.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        Group {
            if sortedDocs.isEmpty {
                ContentUnavailableView(
                    "No Documents Yet",
                    systemImage: "doc.text.fill",
                    description: Text("Registration, insurance cards, receipts — save photos of anything worth keeping on file.")
                )
            } else {
                List {
                    ForEach(sortedDocs) { doc in
                        NavigationLink {
                            DocumentDetailView(document: doc)
                        } label: {
                            HStack(spacing: 12) {
                                if let data = doc.imageData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 132) {
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
                    .onDelete { offsets in pendingDeletion = offsets.map { sortedDocs[$0] } }
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "document") { deleteDocs($0) }
        .saveErrorAlert($saveError)
    }

    private func deleteDocs(_ docs: [VehicleDocument]) {
        for doc in docs {
            context.delete(doc)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}

struct DocumentDetailView: View {
    let document: VehicleDocument
    @State private var showingEdit = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEditDocumentView(vehicle: document.vehicle, document: document)
        }
    }
}
