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
    @State private var remindOn: Bool
    @State private var remindDate: Date
    @State private var showRemindersDenied = false
    @Environment(\.todoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true

    init(task: TaskItem? = nil, category: TaskCategory) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _category = State(initialValue: task?.category ?? category)
        _starred = State(initialValue: task?.isStarred ?? false)
        _note = State(initialValue: task?.note ?? "")
        _photoFilename = State(initialValue: task?.imageFilename)
        _remindOn = State(initialValue: task?.reminderDate != nil && task?.reminderID != nil)
        _remindDate = State(initialValue: task?.reminderDate
            ?? Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(3600))
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
                reminderSection
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
            .alert("Reminders access is off", isPresented: $showRemindersDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button("Not now", role: .cancel) { }
            } message: {
                Text("Allow Todos to use Reminders in Settings, and your reminders will appear in Apple’s Reminders app.")
            }
            .alert("Couldn’t save task", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Turning this on adds the task to Apple's Reminders app, which then alerts you at the chosen time.
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { remindOn }, set: { wantsReminder in
                if wantsReminder {
                    Task {
                        if await ReminderService.shared.requestAccess() {
                            withAnimation(.snappy) { remindOn = true }
                        } else {
                            showRemindersDenied = true
                        }
                    }
                } else {
                    withAnimation(.snappy) { remindOn = false }
                }
            })) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me").font(.headline)
                        Text("Adds it to the Reminders app").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: remindOn ? "bell.fill" : "bell").font(.title3).foregroundStyle(theme.deep)
                        .symbolEffect(.bounce, value: remindOn)
                }
            }
            .tint(theme.deep)
            if remindOn {
                DatePicker("When", selection: $remindDate, in: min(Date(), remindDate)..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).modifier(GlassCard())
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
        var reminderID = task?.reminderID
        var reminderDate: Date?
        if remindOn {
            guard let linked = ReminderService.shared.upsert(id: reminderID, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                                             note: note.trimmingCharacters(in: .whitespacesAndNewlines), due: remindDate) else {
                store.errorMessage = "The reminder couldn’t be added to the Reminders app. Please try again."
                return
            }
            reminderID = linked
            reminderDate = remindDate
        } else {
            ReminderService.shared.remove(id: reminderID)
            reminderID = nil
        }
        let extras = TaskExtras(note: note, imageFilename: filename, reminderDate: reminderDate, reminderID: reminderID)
        let saved: Bool
        if let task {
            saved = store.edit(task.id, title: title, category: category, isStarred: starred, extras: extras)
        } else {
            saved = store.add(title: title, category: category, isStarred: starred, extras: extras)
        }
        if saved { dismiss() }
    }
}
