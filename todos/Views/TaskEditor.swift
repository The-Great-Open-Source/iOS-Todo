import PhotosUI
import SwiftUI

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TaskStore.self) private var store
    @FocusState private var focused: Bool
    let task: TaskItem?
    @State private var title: String
    @State private var category: TaskCategory
    @State private var starred: Bool
    @State private var note: String
    @State private var photoFilename: String?
    @State private var pickedData: Data?
    @State private var pickedPreview: CGImage?
    @State private var pickerItem: PhotosPickerItem?
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    init(task: TaskItem? = nil, category: TaskCategory) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? category)
        _starred = State(initialValue: task?.isStarred ?? false)
        _note = State(initialValue: task?.note ?? "")
        _photoFilename = State(initialValue: task?.imageFilename)
    }

    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
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
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(16).modifier(GlassCard())
                    .accessibilityLabel("Note")
                photoSection
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
            }
            .scrollDismissesKeyboard(.interactively)
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

    /// A photo for the tile: pick one, see it, or take it away again.
    @ViewBuilder
    private var photoSection: some View {
        if pickedPreview != nil || photoFilename != nil {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let pickedPreview {
                        Image(decorative: pickedPreview, scale: 1).resizable().scaledToFill()
                    } else if let photoFilename {
                        TaskPhotoView(filename: photoFilename)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button {
                    withAnimation(.snappy) { pickedData = nil; pickedPreview = nil; photoFilename = nil; pickerItem = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
                        .frame(width: 36, height: 36).glassEffect(.regular.interactive(), in: Circle())
                }
                .padding(10).accessibilityLabel("Remove photo")
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Add a photo", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).modifier(GlassCard())
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let preview = TaskImageStorage.cgImage(from: data, maxPixels: 900) else { return }
                    withAnimation(.snappy) { pickedData = data; pickedPreview = preview }
                }
            }
        }
    }

    private func save() {
        guard valid else { return }
        var filename = photoFilename
        if let pickedData {
            guard let stored = try? store.images.save(pickedData) else {
                store.errorMessage = "That photo couldn’t be saved. Please try a different one."
                return
            }
            filename = stored
        }
        let extras = TaskExtras(note: note, imageFilename: filename)
        let saved: Bool
        if let task {
            saved = store.edit(task.id, title: title, category: category, isStarred: starred, extras: extras)
        } else {
            saved = store.add(title: title, category: category, isStarred: starred, extras: extras)
        }
        if saved { dismiss() }
    }
}
