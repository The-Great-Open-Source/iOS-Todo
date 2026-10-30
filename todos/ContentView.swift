import SwiftUI

private enum TaskSheet: Identifiable {
    case edit(TaskItem), settings, categories, completed
    var id: String {
        switch self {
        case .edit(let task): task.id.uuidString
        case .settings: "settings"
        case .categories: "categories"
        case .completed: "completed"
        }
    }
}

struct ContentView: View {
    @Environment(TaskStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showCompleted") private var showCompleted = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @State private var sheet: TaskSheet?
    @State private var reordering = false
    @State private var celebration: CelebrationEvent?
    @State private var ledger = CelebrationLedger()
    @State private var combo = 0
    @State private var lastCompletion = Date.distantPast
    @State private var slideForward = true
    @State private var highlightID: UUID?
    @State private var showingAdd = false
    @Namespace private var zoomNamespace
    @ScaledMetric(relativeTo: .title) private var titleSize = 32

    private var category: TaskCategory { store.selectedCategory }
    private var theme: TodoTheme { category.theme }
    private var visibleTasks: [TaskItem] {
        store.items(in: category, showCompleted: reordering || showCompleted, sortingCompleted: !reordering)
            .filter { !$0.isArchived(at: currentDate) }
    }
    private var activeItems: [TaskItem] {
        store.items(in: category).filter { !$0.isArchived(at: currentDate) }
    }
    private var remaining: Int { store.items(in: category, showCompleted: false).count }
    /// Starred categories first, then the rest, so swiping reaches every tab.
    private var orderedCategories: [TaskCategory] { store.mainCategories + store.moreCategories }
    private var categoryBinding: Binding<TaskCategory> {
        Binding(get: { category }, set: { selectCategory($0) })
    }
    private var undoToken: String? {
        guard store.deletedTask != nil || store.deletedCategory != nil else { return nil }
        return "\(store.deletedCategory?.category.id ?? "")|\(store.deletedTask?.id.uuidString ?? "")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryRow
            tabContent
        }
        .background { AmbientBackground() }
        .tint(theme.deep)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { currentDate = Date() }
            else { celebration = nil }
        }
        .onChange(of: store.tasks) { old, new in
            let known = Set(old.map(\.id))
            guard let created = new.first(where: { !known.contains($0.id) }) else { return }
            // New work moves the finish line, so the next run of wins deserves its own cheers.
            ledger.rearm(category: created.category.id)
            // A task restored by Undo keeps its old creation date; only brand-new ones get the welcome.
            guard created.createdAt > Date().addingTimeInterval(-5) else { return }
            Task {
                // Wait for the editor sheet to finish closing so the arrival is actually seen.
                try? await Task.sleep(for: .seconds(0.5))
                highlightID = created.id
                RewardFeedback.shared.added(haptics: hapticsEnabled)
                try? await Task.sleep(for: .seconds(1.8))
                if highlightID == created.id { highlightID = nil }
            }
        }
        .task(id: store.tasks) {
            currentDate = Date()
            while !Task.isCancelled {
                let now = Date()
                let next = store.tasks.compactMap { task -> Date? in
                    guard task.isCompleted, let completed = task.completedAt else { return nil }
                    let expiry = completed.addingTimeInterval(600)
                    return expiry > now ? expiry : nil
                }.min()
                guard let next else { return }
                do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) }
                catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { currentDate = Date() }
            }
        }
        .task(id: undoToken) {
            guard undoToken != nil else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { store.dismissUndo() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .overlay {
            if let celebration {
                CompletionCelebration(event: celebration) {
                    withAnimation(.easeOut(duration: 0.2)) { self.celebration = nil }
                }
                .id(celebration.id)
                .transition(.opacity)
            }
        }
        .task(id: celebration?.id) {
            guard let current = celebration else { return }
            do { try await Task.sleep(for: .seconds(reduceMotion ? 1.8 : current.milestone.totalDuration)) } catch { return }
            guard celebration?.id == current.id else { return }
            withAnimation(.easeOut(duration: 0.2)) { celebration = nil }
        }
        #if DEBUG
        .task { await runDemoIfRequested() }
        #endif
        .sheet(item: $sheet) { item in
            switch item {
            case .edit(let task): TaskEditor(task: task, category: category)
            case .settings: SettingsView()
            case .categories: CategoryManager()
            case .completed: CompletedTasksView(category: category)
            }
        }
        .fullScreenCover(isPresented: $showingAdd) {
            TaskEditor(category: category).navigationTransition(.zoom(sourceID: "add", in: zoomNamespace))
        }
        .alert("Your tasks", isPresented: Binding(get: { store.errorMessage != nil && sheet == nil && !showingAdd }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .environment(\.todoTheme, theme)
    }

    // MARK: Actions

    private func selectCategory(_ new: TaskCategory) {
        guard new != category else { return }
        let order = orderedCategories
        slideForward = (order.firstIndex(of: new) ?? 0) > (order.firstIndex(of: category) ?? 0)
        RewardFeedback.shared.tabChanged(haptics: hapticsEnabled)
        // Let the slide direction render first, so the outgoing page leaves the right way.
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.1)) {
                store.selectCategory(new)
                reordering = false
                celebration = nil
            }
        }
    }

    private func stepCategory(_ offset: Int) {
        let order = orderedCategories
        guard let index = order.firstIndex(of: category), order.indices.contains(index + offset) else { return }
        selectCategory(order[index + offset])
    }

    private func toggleTask(_ task: TaskItem) {
        let items = activeItems
        let before = items.filter(\.isCompleted).count
        withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.16)) {
            store.toggle(task.id)
        }
        guard let updated = store.tasks.first(where: { $0.id == task.id }),
              updated.isCompleted != task.isCompleted else { return }
        guard updated.isCompleted else {
            combo = 0
            RewardFeedback.shared.reopened(haptics: hapticsEnabled, sound: soundEnabled)
            return
        }
        let now = Date()
        combo = now.timeIntervalSince(lastCompletion) < 6 ? combo + 1 : 1
        lastCompletion = now
        let ids = Set(items.map(\.id))
        let after = store.items(in: category).filter { ids.contains($0.id) && $0.isCompleted }.count
        if let milestone = ledger.claim(before: before, after: after, total: items.count, category: category.id) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                celebration = CelebrationEvent(milestone: milestone)
            }
            RewardFeedback.shared.celebrate(milestone, haptics: hapticsEnabled, sound: soundEnabled)
        } else {
            RewardFeedback.shared.completed(combo: combo, haptics: hapticsEnabled, sound: soundEnabled)
        }
    }

    #if DEBUG
    /// Launch with `-demoComplete 4 -demoInterval 7` to check off tasks through the real code path.
    private func runDemoIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> Double? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return Double(args[index + 1])
        }
        if args.contains("-demoCategories"), store.categories.count == 1 {
            let seed: [(String, [String])] = [
                ("Work", ["Send the proposal", "Review pull requests"]), ("Groceries", ["Milk and eggs", "Fresh fruit"]),
                ("Fitness plan this summer", ["Morning run", "Stretching"]), ("Reading list", ["Finish the novel"]),
                ("Travel ideas", ["Look at flights"]), ("Birthday gifts", ["Order a present"]), ("Kavindu", ["Call back"]),
            ]
            for (title, tasks) in seed {
                store.addCategory(title: title)
                if let created = store.categories.last { for task in tasks { store.add(title: task, category: created) } }
            }
            store.selectCategory(.today)
        }
        if let index = value("-demoSelect") {
            try? await Task.sleep(for: .seconds(value("-demoDelay") ?? 1.5))
            if orderedCategories.indices.contains(Int(index)) { selectCategory(orderedCategories[Int(index)]) }
        }
        let pause = value("-demoDelay") ?? 1.5
        if args.contains("-demoOpenAdd") { try? await Task.sleep(for: .seconds(pause)); showingAdd = true }
        if args.contains("-demoAdd") { try? await Task.sleep(for: .seconds(pause)); store.add(title: "Water the plants", category: category) }
        if args.contains("-demoDelete") { try? await Task.sleep(for: .seconds(pause)); if let first = visibleTasks.first { deleteTask(first) } }
        guard let count = value("-demoComplete") else { return }
        try? await Task.sleep(for: .seconds(value("-demoDelay") ?? 2))
        for _ in 0..<Int(count) {
            guard let task = visibleTasks.first(where: { !$0.isCompleted }) else { break }
            toggleTask(task)
            try? await Task.sleep(for: .seconds(value("-demoInterval") ?? 1.2))
        }
    }
    #endif

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My Tasks")
                        .font(.system(size: titleSize, weight: .bold)).tracking(-1)
                    Text(remaining == 1 ? "1 task left" : "\(remaining) tasks left")
                        .font(.caption).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("remainingCount")
                }
                Spacer(minLength: 12)
                if reordering {
                    Button("Done") { reordering = false }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                } else {
                    Menu {
                        Button("Reorder Tasks", systemImage: "arrow.up.arrow.down") { reordering = true }
                            .disabled(store.items(in: category).count < 2)
                        Button("Completed tasks", systemImage: "checkmark.circle") { sheet = .completed }
                        Button("Categories", systemImage: "square.grid.2x2") { sheet = .categories }
                        Button("Settings", systemImage: "gearshape") { sheet = .settings }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Task options")
                }
            }
            if reordering {
                Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                progressLine
            }
        }
        .padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 18)
        .contentShape(Rectangle())
        .simultaneousGesture(tabSwipe, including: reordering ? .subviews : .all)
    }

    /// One thin line that fills as the list gets done.
    private var progressLine: some View {
        let items = activeItems
        let done = items.filter(\.isCompleted).count
        let progress = items.isEmpty ? 0 : Double(done) / Double(items.count)
        return Capsule()
            .fill(.primary.opacity(0.08))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(progress >= 1 ? TodoPalette.done : theme.accent)
                        .frame(width: max(0, proxy.size.width * progress))
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.12), value: progress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue("\(done) of \(items.count) done")
    }

    // MARK: Categories

    private var categoryRow: some View {
        HStack(spacing: 8) {
            CategorySelector(categories: orderedCategories, selection: categoryBinding)
            Button { sheet = .categories } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Manage categories")
        }
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    // MARK: List

    /// The current tab's tasks. Drag sideways to move through every tab; the page slides the way you drag.
    private var tabContent: some View {
        ZStack {
            taskList
                .id(category.id)
                .transition(reduceMotion ? .opacity : .push(from: slideForward ? .trailing : .leading))
        }
        .clipped()
    }

    /// Drag sideways over the title area (or an empty list) to move through the tabs. Over the task
    /// tiles a left swipe removes the tile instead, so the list itself is left alone.
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                let flick = abs(value.predictedEndTranslation.width)
                guard abs(dx) > 30, abs(dx) > 70 || flick > 180, abs(dx) > abs(dy) * 1.5 else { return }
                stepCategory(dx < 0 ? 1 : -1)
            }
    }

    private func deleteTask(_ task: TaskItem) {
        RewardFeedback.shared.removed(haptics: hapticsEnabled)
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.05)) { store.delete(task) }
    }

    @ViewBuilder
    private var taskList: some View {
        let tasks = visibleTasks
        if tasks.isEmpty {
            emptyState
        } else {
            List {
                ForEach(tasks) { task in
                    TaskRow(task: task, arrived: task.id == highlightID, toggle: { toggleTask(task) }, edit: { sheet = .edit(task) })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 12, trailing: 24))
                    // Swipe the tile right to left: a short pull reveals the buttons, a long pull removes it.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { deleteTask(task) } label: { Label("Remove", systemImage: "trash") }
                        Button { sheet = .edit(task) } label: { Label("Edit", systemImage: "pencil") }.tint(theme.deep)
                    }
                    .contextMenu {
                        Button("Edit Task", systemImage: "pencil") { sheet = .edit(task) }
                        Button("Delete Task", systemImage: "trash", role: .destructive) { deleteTask(task) }
                    }
                    .accessibilityAction(named: "Edit task") { sheet = .edit(task) }
                    .accessibilityAction(named: "Delete task") { deleteTask(task) }
                }
                .onMove { offsets, destination in store.move(in: category, from: offsets, to: destination, visibleIDs: tasks.map(\.id)) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .environment(\.editMode, .constant(reordering ? .active : .inactive))
        }
    }

    private var emptyState: some View {
        let hasTasks = !store.items(in: category).isEmpty
        return GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    EmptyChecklistIllustration().padding(.bottom, 24)
                    Text(hasTasks ? "All done for now." : "A little breathing room.")
                        .font(.system(.title2, weight: .semibold)).tracking(-0.7)
                        .multilineTextAlignment(.center)
                    Text(hasTasks
                         ? "Everything is checked off. Your completed\ntasks are safely tucked away."
                         : "Nothing here yet. Add your first task\nand make room for what matters.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .lineSpacing(5).multilineTextAlignment(.center).padding(.top, 12)
                    if hasTasks {
                        Button("View completed tasks") { sheet = .completed }
                            .font(.subheadline.weight(.semibold)).padding(.top, 18)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(tabSwipe, including: reordering ? .subviews : .all)
        }
    }

    // MARK: Bottom

    private var bottomActions: some View {
        VStack(spacing: 14) {
            if store.deletedCategory != nil {
                undoBanner("Category deleted") { store.undoCategoryDeletion() }
            } else if store.deletedTask != nil {
                undoBanner("Task deleted") { store.undoDelete() }
            }
            if store.canDeleteCompletedCategory(category) {
                Button(role: .destructive) {
                    if store.deleteCompletedCategory(category) {
                        celebration = nil
                        reordering = false
                    }
                } label: {
                    Label("Delete category", systemImage: "trash")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(.red)
                .accessibilityHint("Deletes this category and any completed tasks in it. Undo is available afterward.")
            }
            Button {
                RewardFeedback.shared.pressed(haptics: hapticsEnabled)
                showingAdd = true
            } label: {
                AddTaskLabel()
            }
            .buttonStyle(PrimaryTaskButtonStyle())
            .matchedTransitionSource(id: "add", in: zoomNamespace)
            .accessibilityIdentifier("addTaskButton")
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.2), value: undoToken)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
    }

    private func undoBanner(_ message: String, undo: @escaping () -> Void) -> some View {
        HStack {
            Text(message).font(.subheadline)
            Spacer()
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .font(.subheadline.weight(.semibold))
        }
        .padding(16).modifier(GlassCard())
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// The plus spins a quarter turn and swells while the button is held, then the editor zooms out of the button.
private struct AddTaskLabel: View {
    @Environment(\.buttonIsPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 18, weight: .medium))
                .rotationEffect(.degrees(pressed && !reduceMotion ? 90 : 0))
                .scaleEffect(pressed && !reduceMotion ? 1.25 : 1)
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.5), value: pressed)
            Text("Add Task").font(.system(.headline, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 24).padding(.vertical, 19)
    }
}

#Preview {
    ContentView().environment(TaskStore())
}
