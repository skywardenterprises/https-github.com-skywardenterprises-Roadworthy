import SwiftUI
import SwiftData

struct AddEditExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing expense, pass it in. Nil means "creating new".
    var expense: ExpenseRecord?

    @State private var category: ExpenseCategory = .insurance
    @State private var categoryOther = ""
    @State private var date = Date.now
    @State private var amountText = ""
    @State private var notes = ""
    @State private var receiptPhotoData: Data?
    @State private var isLoadingPhoto = false

    @State private var showingValidationAlert = false
    @State private var validationTitle = ""
    @State private var validationMessage = ""
    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { expense != nil }

    private var validationIssue: String? {
        if (Double(amountText) ?? 0) <= 0 {
            return L("Enter the amount to save.")
        }
        if isLoadingPhoto {
            return L("Waiting for the receipt photo to finish loading…")
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(category, category == .other ? categoryOther.trimmed : "", date, Double(amountText), notes, receiptPhotoData)
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Text(LocalizedStringKey(category.rawValue)).tag(category)
                        }
                    }
                    if category == .other {
                        TextField("Describe the expense (e.g. Parking)", text: $categoryOther)
                    }
                    WheelDatePicker(title: "Date", date: $date)
                    HStack {
                        Text("Amount")
                        Spacer()
                        AutoDecimalField(title: "Amount", text: $amountText)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                    ReceiptPhotoField(photoData: $receiptPhotoData, isLoading: $isLoadingPhoto)
                }

                if isEditing {
                    Section {
                        Button("Delete Expense", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this expense?", isPresented: $showingDeleteConfirm) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(isEditing ? "Edit Expense" : "Log Expense"))
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
            .alert(validationTitle, isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func loadExistingValues() {
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let expense else { return }
        category = expense.category
        categoryOther = expense.categoryOther
        date = expense.date
        amountText = expense.amount == 0 ? "" : String(expense.amount)
        notes = expense.notes
        receiptPhotoData = expense.receiptPhotoData
    }

    private func save() {
        guard validationIssue == nil else { return }
        // Same date rules as fuel and maintenance entries.
        if let problem = EntryValidation.dateProblem(date, vehicle: vehicle) {
            validationTitle = problem.title
            validationMessage = problem.message
            showingValidationAlert = true
            return
        }

        let amount = Double(amountText) ?? 0
        if let expense {
            expense.category = category
            expense.categoryOther = category == .other ? categoryOther.trimmed : ""
            expense.date = date
            expense.amount = amount
            expense.notes = notes
            expense.receiptPhotoData = receiptPhotoData
        } else {
            let newExpense = ExpenseRecord(category: category, date: date, amount: amount, notes: notes, receiptPhotoData: receiptPhotoData)
            newExpense.categoryOther = category == .other ? categoryOther.trimmed : ""
            newExpense.vehicle = vehicle
            context.insert(newExpense)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let expense {
            context.delete(expense)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
        dismiss()
    }
}
