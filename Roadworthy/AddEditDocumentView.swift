import SwiftUI
import SwiftData
import PhotosUI

/// Add-or-edit form for documents, matching the other forms. Previously a
/// document could only be added; fixing a title meant deleting and re-adding
/// it, which also reset its date.
struct AddEditDocumentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle?

    // If editing an existing document, pass it in. Nil means "creating new".
    var document: VehicleDocument?

    @State private var title = ""
    @State private var notes = ""
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showingPhotoOptions = false
    @State private var showingCamera = false
    @State private var showingPhotoLibraryPicker = false
    @State private var showingPhotoViewer = false

    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { document != nil }

    private var validationIssue: String? {
        if title.trimmed.isEmpty {
            return "Enter a title to save."
        }
        if isLoadingPhoto {
            return "Waiting for the photo to finish loading…"
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(title, notes, imageData)
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    TextField("Title (e.g. Registration)", text: $title)

                    Button {
                        showingPhotoOptions = true
                    } label: {
                        HStack {
                            if isLoadingPhoto {
                                ProgressView()
                                    .frame(width: 60, height: 60)
                            } else if let imageData, let uiImage = ThumbnailCache.image(for: imageData, maxPixel: 180) {
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
                    .foregroundStyle(.primary)
                    .disabled(isLoadingPhoto)
                    .confirmationDialog("Document Photo", isPresented: $showingPhotoOptions, titleVisibility: .visible) {
                        if CameraPicker.isAvailable {
                            Button("Take Photo") { showingCamera = true }
                        }
                        Button("Choose from Library") { showingPhotoLibraryPicker = true }
                        if imageData != nil {
                            Button("View Photo") { showingPhotoViewer = true }
                            Button("Remove Photo", role: .destructive) { imageData = nil }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .sheet(isPresented: $showingCamera) {
                        CameraPicker(imageData: $imageData)
                            .ignoresSafeArea()
                    }
                    .photosPicker(isPresented: $showingPhotoLibraryPicker, selection: $selectedPhoto, matching: .images)
                    .loadsPickedPhoto($selectedPhoto, into: $imageData, isLoading: $isLoadingPhoto)
                    .sheet(isPresented: $showingPhotoViewer) {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            NavigationStack {
                                ScrollView {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .padding()
                                }
                                .navigationTitle("Document Photo")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") { showingPhotoViewer = false }
                                    }
                                }
                            }
                        }
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                }

                // No Delete button here: this form opens from the document's
                // detail screen, which would still be showing the deleted
                // document afterward. Documents are deleted by swiping in the
                // list, with a confirmation.
            }
            .navigationTitle(isEditing ? "Edit Document" : "Add Document")
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
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let document else { return }
        title = document.title
        notes = document.notes
        imageData = document.imageData
    }

    private func save() {
        guard validationIssue == nil else { return }
        if let document {
            document.title = title.trimmed
            document.notes = notes
            document.imageData = imageData
        } else {
            let doc = VehicleDocument(title: title.trimmed, imageData: imageData, notes: notes)
            doc.vehicle = vehicle
            context.insert(doc)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

}
