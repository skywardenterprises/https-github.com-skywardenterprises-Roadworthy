import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var expenseToEdit: ExpenseRecord?

    private var sortedExpenses: [ExpenseRecord] {
        vehicle.expenses.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedExpenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses Logged",
                    systemImage: "dollarsign.circle",
                    description: Text("Use the + button to log insurance, parking, tolls, etc.")
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
                    .onDelete(perform: deleteExpenses)
                }
            }
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $expenseToEdit) { expense in
            AddEditExpenseView(vehicle: vehicle, expense: expense)
        }
    }

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedExpenses[index])
        }
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

    private var isEditing: Bool { expense != nil }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $notes, axis: .vertical)
                ReceiptPhotoField(photoData: $receiptPhotoData)

                if isEditing {
                    Section {
                        Button("Delete Expense", role: .destructive) {
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: loadExistingValues)
        }
    }

    private func loadExistingValues() {
        guard let expense else { return }
        category = expense.category
        date = expense.date
        amountText = expense.amount == 0 ? "" : String(expense.amount)
        notes = expense.notes
        receiptPhotoData = expense.receiptPhotoData
    }

    private func save() {
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
        dismiss()
    }

    private func deleteAndDismiss() {
        if let expense {
            context.delete(expense)
        }
        dismiss()
    }
}
