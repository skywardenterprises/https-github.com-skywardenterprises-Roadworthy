import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var expenseToEdit: ExpenseRecord?
    @State private var pendingDeletion: [ExpenseRecord] = []
    @State private var saveError: String?

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
                                    Text(expense.amount, format: .currency(code: AppCurrency.code))
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
        .saveErrorAlert($saveError)
        .sheet(item: $expenseToEdit) { expense in
            AddEditExpenseView(vehicle: vehicle, expense: expense)
        }
    }

    private func deleteExpenses(_ expenses: [ExpenseRecord]) {
        for expense in expenses {
            context.delete(expense)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}
