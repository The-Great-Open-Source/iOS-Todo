import SwiftUI

/// Add a task by talking. Say it the way you would to a person, "wash my clothes today evening near 5pm",
/// and the sheet shows the task it understood, with its time, list, and star, to confirm or fix before adding.
struct VoiceTaskSheet: View {
    var category: TaskCategory
    /// Called with the list the task landed in, once it has been added.
    var onAdded: (TaskCategory) -> Void
    /// Skips the microphone and starts from this sentence, for previews and screenshots.
    var preset: String?

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.todoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var dictation = VoiceDictation()
    @State private var phase: Phase = .listening
    @State private var heardText = ""
    @State private var title = ""
    @State private var due: Date?
    @State private var hasSpokenTime = true
    @State private var chosen: TaskCategory?
    @State private var starred = false
    @State private var adding = false

    private enum Phase { case listening, review }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if phase == .listening { listening } else { review }
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AmbientBackground() }
            .navigationTitle(phase == .listening ? "Say your task" : "Here’s what I got")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dictation.reset(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if let preset { understand(preset) } else { await listen() }
        }
        .onDisappear { dictation.reset() }
        .animation(reduceMotion ? nil : .snappy, value: phase)
    }

    // MARK: Listening

    private var listening: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)
            Button {
                if dictation.isListening { RewardFeedback.shared.pressed(haptics: hapticsEnabled); dictation.stop() }
                else { Task { await listen() } }
            } label: {
                ZStack {
                    Circle().fill(theme.accent.opacity(0.18))
                        .scaleEffect(1 + (reduceMotion ? 0 : dictation.level) * 0.9)
                        .animation(.easeOut(duration: 0.12), value: dictation.level)
                    Circle().fill(theme.accent.opacity(0.14)).scaleEffect(1.25 + (reduceMotion ? 0 : dictation.level) * 0.5)
                        .animation(.easeOut(duration: 0.18), value: dictation.level)
                    Image(systemName: dictation.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 40, weight: .medium)).foregroundStyle(.primary)
                        .symbolEffect(.variableColor.iterative, isActive: dictation.isListening && !reduceMotion)
                        .frame(width: 112, height: 112)
                        .glassEffect(.regular.tint(theme.accent.opacity(0.22)).interactive(), in: Circle())
                }
                .frame(width: 180, height: 180)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(dictation.isListening ? "Stop listening" : "Start listening")

            VStack(spacing: 10) {
                Text(statusText).font(.subheadline).foregroundStyle(.secondary)
                if !dictation.transcript.isEmpty {
                    Text(dictation.transcript).font(.system(.title2, weight: .medium)).multilineTextAlignment(.center)
                        .transition(.opacity)
                } else if dictation.isListening {
                    Text("“Call mom tomorrow at 5 pm”").font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)

            if dictation.isListening {
                Button("Done") { dictation.stop() }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                Button("Type it instead", systemImage: "keyboard") { understand(heardText) ; phase = .review }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
        }
    }

    private var statusText: String {
        switch dictation.state {
        case .idle: "Tap the microphone to try again"
        case .starting: "Getting ready…"
        case .listening: dictation.transcript.isEmpty ? "Listening…" : "I’m listening…"
        case .denied(let message), .unavailable(let message): message
        }
    }

    private func listen() async {
        await dictation.start {
            let spoken = dictation.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return }
            understand(spoken)
        }
        if case .denied = dictation.state {
            // Offer the way to switch access on; the message above explains why.
        }
    }

    private func understand(_ sentence: String) {
        heardText = sentence
        let parsed = VoiceTaskParser.parse(sentence, categories: store.categories)
        title = parsed.title
        due = parsed.due
        hasSpokenTime = parsed.hasSpokenTime
        chosen = parsed.category
        starred = parsed.isStarred
        RewardFeedback.shared.added(haptics: hapticsEnabled)
        phase = .review
    }

    // MARK: Review

    private var destination: TaskCategory { chosen ?? category }
    private var valid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Task", text: $title, axis: .vertical)
                .font(.system(.title2, weight: .medium)).lineLimit(1...4)
                .padding(20).modifier(GlassCard())
                .accessibilityLabel("Task title")
            if heardText != title {
                Text("You said “\(heardText)”").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            VStack(spacing: 0) {
                whenRow
                Divider().padding(.leading, 52)
                listRow
                Divider().padding(.leading, 52)
                starRow
            }
            .padding(.horizontal, 16).modifier(GlassCard())

            Button { Task { await add() } } label: {
                Text("Add Task").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            .buttonStyle(PrimaryTaskButtonStyle())
            .disabled(!valid || adding)
            .accessibilityIdentifier("voiceAddButton")

            Button("Say it again", systemImage: "mic") {
                phase = .listening
                Task { await listen() }
            }
            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var whenRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: due == nil ? "bell.slash" : "bell.fill").font(.title3).foregroundStyle(theme.deep).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(due.map { Self.describe($0) } ?? "No reminder").font(.headline)
                    if due != nil {
                        Text(hasSpokenTime ? "Adds to the Reminders app" : "No time said, so I picked 9:00 AM")
                            .font(.caption).foregroundStyle(.secondary)
                        if ReminderService.shared.isDenied {
                            Text("Reminders access is off, so no alert will be set.").font(.caption).foregroundStyle(.red)
                        }
                    } else {
                        Text("Say a day or time to be reminded").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if due != nil {
                    Button { withAnimation(.snappy) { due = nil } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Remove reminder")
                }
            }
            if let current = due {
                DatePicker("When", selection: Binding(get: { current }, set: { due = $0; hasSpokenTime = true }),
                           in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.compact)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 38)
            }
        }
        .padding(.vertical, 14)
    }

    private var listRow: some View {
        HStack(spacing: 14) {
            Image(systemName: destination.symbol).font(.title3).foregroundStyle(theme.deep).frame(width: 24)
            Text("List").font(.headline)
            Spacer()
            Picker("List", selection: Binding(get: { destination }, set: { chosen = $0 })) {
                ForEach(store.categories) { item in Label(item.title, systemImage: item.symbol).tag(item) }
            }
            .pickerStyle(.menu).labelsHidden()
        }
        .padding(.vertical, 8)
    }

    private var starRow: some View {
        Toggle(isOn: $starred.animation(.spring(duration: 0.35, bounce: 0.4))) {
            Label {
                Text("Star it").font(.headline)
            } icon: {
                Image(systemName: starred ? "star.fill" : "star").font(.title3).foregroundStyle(TodoPalette.gold)
                    .symbolEffect(.bounce, value: starred).frame(width: 24)
            }
        }
        .tint(TodoPalette.gold).padding(.vertical, 10)
    }

    // MARK: Saving

    private func add() async {
        guard valid, !adding else { return }
        adding = true
        defer { adding = false }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var extras = TaskExtras()
        if let due, due > Date(), await ReminderService.shared.requestAccess(),
           let id = ReminderService.shared.upsert(id: nil, title: cleaned, note: nil, due: due) {
            extras.reminderDate = due
            extras.reminderID = id
        }
        if store.add(title: cleaned, category: destination, isStarred: starred, extras: extras) {
            dictation.reset()
            onAdded(destination)
            dismiss()
        } else {
            ReminderService.shared.remove(id: extras.reminderID)
        }
    }

    /// "Today, 5:00 PM", "Tomorrow, 9:00 AM", "Fri 27 Nov, 4:00 PM".
    static func describe(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow, \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))), \(time)"
    }
}
