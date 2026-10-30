import SwiftUI

struct CompletedTasksView: View {
    let category: TaskCategory
    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var completed: [TaskItem] {
        store.items(in: category).filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(completed) { task in
                        Button { store.toggle(task.id) } label: {
                            Label(task.title, systemImage: "arrow.uturn.backward.circle")
                                .foregroundStyle(.primary).padding(.vertical, 8)
                        }
                        .accessibilityLabel("Reopen \(task.title)")
                    }
                } footer: {
                    Text("Completed tasks leave your checklist after 10 minutes. Tap a task here to reopen it. Today never resets at midnight.")
                }
            }
            .overlay {
                if completed.isEmpty {
                    ContentUnavailableView("No completed tasks", systemImage: "checkmark.circle")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .navigationTitle("Completed · \(category.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Couldn’t reopen task", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}
