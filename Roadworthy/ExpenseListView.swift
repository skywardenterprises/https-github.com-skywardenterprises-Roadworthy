import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var expenseToEdit: ExpenseRecord?
    @State private var pendingDeletion: [ExpenseRecord] = []

    private var sortedExpenses: [ExpenseRecord] {
        vehicle.expenses.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedExpenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses Yet",
                    systemImage: "dollarsign.circle.fill",
                    description: Text("Insurance, parking, tolls — the little costs add up. Log them here to see the full picture.")
                )
            } else {
                List {
                    ForEach(sortedExpenses) { expense in
                        Button {
                            expenseToEdit = expense
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(expense.category.rawValue).font(.headline)
                                    if expense.receiptPhotoData != nil {
                                        Image(systemName: "paperclip")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(expense.amount, format: .currency(code: "USD"))
                                        .foregroundStyle(.secondary)
                                }
                                Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !expense.notes.isEmpty {
                                    Text(expense.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in pendingDeletion = offsets.map { sortedExpenses[$0] } }
                }
            }
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "expense") { deleteExpenses($0) }
        .sheet(item: $expenseToEdit) { expense in
            AddEditExpenseView(vehicle: vehicle, expense: expense)
        }
    }

    private func deleteExpenses(_ expenses: [ExpenseRecord]) {
        for expense in expenses {
            context.delete(expense)
        }
        Haptics.delete()
    }
}

struct AddEditExpenseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing expense, pass it in. Nil means "creating new".
    var expense: ExpenseRecord?

    @State private var category: ExpenseCategory = .insurance
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
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { expense != nil }

    private var validationIssue: String? {
        if (Double(amountText) ?? 0) <= 0 {
            return "Enter the amount to save."
        }
        if isLoadingPhoto {
            return "Waiting for the receipt photo to finish loading…"
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(category, date, Double(amountText), notes, receiptPhotoData)
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
                            Text(category.rawValue).tag(category)
                        }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
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
            .navigationTitle(isEditing ? "Edit Expense" : "Log Expense")
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
            expense.date = date
            expense.amount = amount
            expense.notes = notes
            expense.receiptPhotoData = receiptPhotoData
        } else {
            let newExpense = ExpenseRecord(category: category, date: date, amount: amount, notes: notes, receiptPhotoData: receiptPhotoData)
            newExpense.vehicle = vehicle
            context.insert(newExpense)
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let expense {
            context.delete(expense)
        }
        Haptics.delete()
        dismiss()
    }
}
