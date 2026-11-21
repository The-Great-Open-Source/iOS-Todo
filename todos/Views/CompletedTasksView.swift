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
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.uturn.backward.circle")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).foregroundStyle(.primary)
                                    if let deletion = task.deletionDate {
                                        Text("Deleted for good \(deletion, format: .relative(presentation: .named, unitsStyle: .wide))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .accessibilityLabel("Reopen \(task.title)")
                    }
                } footer: {
                    Text("Completed tasks leave your checklist after 10 minutes and are deleted for good after 3 days. Tap a task here to reopen it before then; once deleted, it cannot be brought back.")
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
