import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var store
    @FocusState private var focused: Bool
    let task: TaskItem?
    @State private var title: String
    @State private var category: TaskCategory
    @State private var starred: Bool
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    init(task: TaskItem? = nil, category: TaskCategory) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? category)
        _starred = State(initialValue: task?.isStarred ?? false)
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                TextField("What’s on your mind?", text: $title, axis: .vertical)
                    .font(.system(.title2, weight: .medium)).lineLimit(2...5)
                    .padding(20).modifier(GlassCard())
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityLabel("Task title")
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD TO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    Picker("Category", selection: $category) {
                        ForEach(store.categories) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).modifier(GlassCard())
                }
                Toggle(isOn: $starred.animation(.spring(duration: 0.35, bounce: 0.4))) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Star this task").font(.headline)
                            Text("Starred tasks always stay at the top").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: starred ? "star.fill" : "star")
                            .font(.title3).foregroundStyle(TodoPalette.gold)
                            .symbolEffect(.bounce, value: starred)
                    }
                }
                .tint(TodoPalette.gold)
                .padding(.horizontal, 16).padding(.vertical, 12).modifier(GlassCard())
                .onChange(of: starred) { RewardFeedback.shared.tabChanged(haptics: hapticsEnabled) }
                Button(action: save) {
                    Text(task == nil ? "Add Task" : "Save Changes")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                .buttonStyle(PrimaryTaskButtonStyle())
                .disabled(!valid)
                if let task {
                    Button("Delete Task", systemImage: "trash", role: .destructive) {
                        store.delete(task)
                        dismiss()
                    }
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .background { AmbientBackground() }
            .navigationTitle(task == nil ? "Add Task" : "Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .task { focused = true }
            .alert("Couldn’t save task", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard valid else { return }
        let saved: Bool
        if let task {
            saved = store.edit(task.id, title: title, category: category, isStarred: starred)
        } else {
            saved = store.add(title: title, category: category, isStarred: starred)
        }
        if saved { dismiss() }
    }
}
