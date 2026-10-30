import Foundation
import Observation
import Security

/// A second copy of the saved data that lives outside the app's own storage.
protocol SnapshotMirror {
    func write(_ data: Data)
    func read() -> Data?
}

/// Keeps the latest snapshot in the device Keychain. Unlike the app's files, Keychain items survive
/// deleting and reinstalling the app, so a reinstall (or a clean rebuild) can bring your tasks back.
/// The copy never leaves this device and is not synced.
struct KeychainMirror: SnapshotMirror {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.harshanacz.todos.backup",
         kSecAttrAccount as String: "tasks-snapshot"]
    }

    func write(_ data: Data) {
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func read() -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

struct TaskPersistence {
    let url: URL
    var mirror: SnapshotMirror? = nil

    static var local: Self {
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Todos", isDirectory: true)
        return Self(url: directory.appendingPathComponent("tasks.json"), mirror: KeychainMirror())
    }

    /// The file is gone (the app was reinstalled) but a mirrored copy of the data still exists.
    var canRestoreFromMirror: Bool {
        !FileManager.default.fileExists(atPath: url.path) && mirror?.read() != nil
    }

    func loadSnapshot() throws -> TaskSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            if let data = mirror?.read(), let restored = try? JSONDecoder().decode(TaskSnapshot.self, from: data) { return restored }
            return TaskSnapshot(tasks: [], categories: [.today])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let legacy = try? decoder.decode([TaskItem].self, from: data) {
            let used = [TaskCategory.work, .personal].filter { category in legacy.contains { $0.category == category } }
            return TaskSnapshot(tasks: legacy, categories: [.today] + used)
        }
        return try decoder.decode(TaskSnapshot.self, from: data)
    }

    func load() throws -> [TaskItem] { try loadSnapshot().tasks }

    /// Copies the saved file into the mirror. Only called after the file was read successfully.
    func syncMirror() {
        guard let mirror, let data = try? Data(contentsOf: url) else { return }
        mirror.write(data)
    }

    func save(_ tasks: [TaskItem]) throws {
        let used = [TaskCategory.work, .personal].filter { category in tasks.contains { $0.category == category } }
        try save(TaskSnapshot(tasks: tasks, categories: [.today] + used))
    }

    func save(_ snapshot: TaskSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
        mirror?.write(data)
    }

}

struct TaskSnapshot: Codable {
    var tasks: [TaskItem]
    var categories: [TaskCategory]
    var mainCategoryIDs: [String]? = nil
    var selectedCategoryID: String? = nil
}

struct DeletedCategory {
    let category: TaskCategory
    let index: Int
    let tasks: [TaskItem]
    let wasMain: Bool
}

@Observable @MainActor
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var categories: [TaskCategory] = [.today]
    private(set) var mainCategoryIDs: [String] = [TaskCategory.today.id]
    var mainCategories: [TaskCategory] {
        mainCategoryIDs.compactMap { id in categories.first { $0.id == id } }
    }
    var moreCategories: [TaskCategory] { categories.filter { !mainCategoryIDs.contains($0.id) } }
    private(set) var deletedTask: TaskItem?
    private(set) var deletedCategory: DeletedCategory?
    private(set) var selectedCategoryID = TaskCategory.today.id
    var selectedCategory: TaskCategory { categories.first { $0.id == selectedCategoryID } ?? .today }
    var errorMessage: String?
    private let persistence: TaskPersistence
    private var canSave = true

    init(persistence: TaskPersistence? = nil) {
        let persistence = persistence ?? .local
        self.persistence = persistence
        do {
            let restoring = persistence.canRestoreFromMirror
            let isFirstLaunch = !FileManager.default.fileExists(atPath: persistence.url.path) && !restoring
            let snapshot = try persistence.loadSnapshot()
            var seen = Set([TaskCategory.today.id])
            categories = [.today] + snapshot.categories.filter { $0.id != "today" && seen.insert($0.id).inserted }.map { category in
                // Older versions gave every custom category the same generic icon; suggest one from its name instead.
                var category = category
                if category.symbol == CategoryIcon.legacyDefault { category.symbol = CategoryIcon.suggest(for: category.title) }
                return category
            }
            let savedSelection = snapshot.selectedCategoryID ?? UserDefaults.standard.string(forKey: "selectedCategory")
            selectedCategoryID = categories.first { $0.id == savedSelection }?.id ?? TaskCategory.today.id
            mainCategoryIDs = normalizedMainIDs(snapshot.mainCategoryIDs ?? Array(categories.prefix(3).map(\.id)), in: categories)
            tasks = snapshot.tasks.map { task in
                var task = task
                task.category = categories.first { $0.id == task.category.id } ?? .today
                // Older versions did not record completion time. Start their grace period now.
                if task.isCompleted && task.completedAt == nil { task.completedAt = Date() }
                return task
            }
            if restoring || snapshot.tasks != tasks || snapshot.categories.map(\.id) != categories.map(\.id) || snapshot.categories.map(\.symbol) != categories.map(\.symbol) || snapshot.mainCategoryIDs != mainCategoryIDs || snapshot.selectedCategoryID != selectedCategoryID {
                commit(tasks)
            }
            if isFirstLaunch {
                let titles = [
                    "Take a walk outside",
                    "Pick up a few groceries",
                    "Read a chapter",
                    "Plan something to look forward to"
                ]
                let starterTasks = titles.enumerated().map {
                    TaskItem(title: $0.element, category: .today, order: $0.offset)
                }
                commit(starterTasks)
            }
            // Keep the backup in step with what is on disk, even if nothing changed this launch.
            persistence.syncMirror()
        } catch {
            // Preserve the original bytes before permitting a new checklist.
            do {
                let backup = persistence.url.deletingPathExtension()
                    .appendingPathExtension("recovery-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: persistence.url, to: backup)
                errorMessage = "Your saved checklist couldn’t be read. A recovery copy was kept in Todos’ local storage. You can start a new checklist."
            } catch {
                canSave = false
                errorMessage = "Your checklist couldn’t be opened safely. Changes are paused to protect your saved tasks. Please reopen Todos to try again."
            }
        }
    }

    func items(in category: TaskCategory, showCompleted: Bool = true, sortingCompleted: Bool = true) -> [TaskItem] {
        tasks.filter { $0.category == category && (showCompleted || !$0.isCompleted) }
            .sorted {
                if sortingCompleted && $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.createdAt < $1.createdAt
            }
    }

    @discardableResult
    private func commit(_ updated: [TaskItem], categories updatedCategories: [TaskCategory]? = nil, mainIDs: [String]? = nil, selectedID: String? = nil) -> Bool {
        guard canSave else {
            errorMessage = "Changes are paused to protect your saved tasks. Please reopen Todos to try again."
            return false
        }
        do {
            let nextCategories = updatedCategories ?? categories
            let nextMain = normalizedMainIDs(mainIDs ?? mainCategoryIDs, in: nextCategories)
            let candidate = selectedID ?? selectedCategoryID
            let nextSelection = nextCategories.first { $0.id == candidate }?.id ?? TaskCategory.today.id
            try persistence.save(TaskSnapshot(tasks: updated, categories: nextCategories, mainCategoryIDs: nextMain, selectedCategoryID: nextSelection))
            tasks = updated
            categories = nextCategories
            mainCategoryIDs = nextMain
            selectedCategoryID = nextSelection
            return true
        } catch {
            errorMessage = "Your change couldn’t be saved. Please check available device storage and try again."
            return false
        }
    }

    @discardableResult
    func selectCategory(_ category: TaskCategory) -> Bool {
        guard categories.contains(category) else { return false }
        if selectedCategoryID == category.id { return true }
        return commit(tasks, selectedID: category.id)
    }

    /// A custom category can go once nothing in it is still open: it is empty, or everything is done.
    func canDeleteCompletedCategory(_ category: TaskCategory) -> Bool {
        guard category != .today, categories.contains(category) else { return false }
        return tasks.filter { $0.category == category }.allSatisfy(\.isCompleted)
    }

    @discardableResult
    func deleteCompletedCategory(_ category: TaskCategory) -> Bool {
        guard canDeleteCompletedCategory(category), let index = categories.firstIndex(of: category) else { return false }
        let deletion = DeletedCategory(category: category, index: index,
                                       tasks: tasks.filter { $0.category == category },
                                       wasMain: mainCategoryIDs.contains(category.id))
        if commit(tasks.filter { $0.category != category }, categories: categories.filter { $0 != category }) {
            deletedCategory = deletion
            return true
        }
        return false
    }

    func undoCategoryDeletion() {
        guard let deletion = deletedCategory else { return }
        // Avoid conflicting with a newly created category using the same name.
        guard validCategoryTitle(deletion.category.title) else {
            errorMessage = "Rename the new category with this name before restoring the deleted one."
            return
        }
        var restored = categories
        restored.insert(deletion.category, at: min(deletion.index, restored.count))
        let main = deletion.wasMain && mainCategoryIDs.count < 3
            ? mainCategoryIDs + [deletion.category.id] : mainCategoryIDs
        if commit(tasks + deletion.tasks, categories: restored, mainIDs: main, selectedID: deletion.category.id) {
            deletedCategory = nil
        }
    }

    @discardableResult
    func add(title: String, category: TaskCategory) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, categories.contains(category) else { return false }
        let order = (tasks.filter { $0.category == category }.map(\.order).max() ?? -1) + 1
        return commit(tasks + [TaskItem(title: title, category: category, order: order)])
    }

    @discardableResult
    func edit(_ id: UUID, title: String, category: TaskCategory) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, categories.contains(category), let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        var updated = tasks
        if updated[index].category != category {
            updated[index].order = (tasks.filter { $0.category == category }.map(\.order).max() ?? -1) + 1
        }
        updated[index].title = title
        updated[index].category = category
        return commit(updated)
    }

    func toggle(_ id: UUID, at date: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks
        updated[index].isCompleted.toggle()
        updated[index].completedAt = updated[index].isCompleted ? date : nil
        commit(updated)
    }

    func delete(_ task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }) else { return }
        if commit(tasks.filter { $0.id != task.id }) { deletedTask = current }
    }

    /// The undo banners are transient; once they time out the deleted item is let go.
    func dismissUndo() {
        deletedTask = nil
        deletedCategory = nil
    }

    func undoDelete() {
        guard let task = deletedTask else { return }
        var restored = task
        if !categories.contains(restored.category) { restored.category = .today }
        if commit(tasks + [restored]) { deletedTask = nil }
    }

    @discardableResult
    func addCategory(title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validCategoryTitle(title) else { return false }
        let category = TaskCategory(rawValue: UUID().uuidString, title: title, symbol: CategoryIcon.suggest(for: title))
        let main = mainCategoryIDs.count < 3 ? mainCategoryIDs + [category.id] : mainCategoryIDs
        return commit(tasks, categories: categories + [category], mainIDs: main)
    }

    private func normalizedMainIDs(_ ids: [String], in categories: [TaskCategory]) -> [String] {
        var seen = Set<String>()
        let valid = ids.filter { id in categories.contains { $0.id == id } && seen.insert(id).inserted }
        return valid.isEmpty ? [TaskCategory.today.id] : Array(valid.prefix(3))
    }

    @discardableResult
    func setMain(_ category: TaskCategory, enabled: Bool) -> Bool {
        guard categories.contains(category) else { return false }
        let pinned = mainCategoryIDs.contains(category.id)
        if enabled == pinned { return true }
        if enabled {
            guard mainCategoryIDs.count < 3 else { return false }
            return commit(tasks, mainIDs: mainCategoryIDs + [category.id])
        }
        guard mainCategoryIDs.count > 1 else { return false }
        return commit(tasks, mainIDs: mainCategoryIDs.filter { $0 != category.id })
    }

    @discardableResult
    func renameCategory(_ category: TaskCategory, title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard category != .today, validCategoryTitle(title, excluding: category),
              let index = categories.firstIndex(of: category) else { return false }
        var updated = categories
        updated[index].title = title
        updated[index].symbol = CategoryIcon.suggest(for: title)
        let renamedTasks = tasks.map { task in
            var task = task
            if task.category == category { task.category = updated[index] }
            return task
        }
        return commit(renamedTasks, categories: updated)
    }

    func validCategoryTitle(_ title: String, excluding category: TaskCategory? = nil) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title.count <= 24 && !categories.contains {
            $0 != category && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    @discardableResult
    func removeCategory(_ category: TaskCategory) -> Bool {
        guard category != .today, categories.contains(category) else { return false }
        var nextOrder = (tasks.filter { $0.category == .today }.map(\.order).max() ?? -1) + 1
        var updated = tasks
        for index in updated.indices where updated[index].category == category {
            updated[index].category = .today
            updated[index].order = nextOrder
            nextOrder += 1
        }
        return commit(updated, categories: categories.filter { $0 != category })
    }

    func move(in category: TaskCategory, from offsets: IndexSet, to destination: Int, visibleIDs: [UUID]? = nil) {
        let all = items(in: category, sortingCompleted: false)
        let visible = visibleIDs.map(Set.init)
        var ordered = all.filter { visible?.contains($0.id) ?? true }
        guard destination >= 0, destination <= ordered.count, offsets.allSatisfy({ ordered.indices.contains($0) }) else { return }
        let moving = offsets.sorted().map { ordered[$0] }
        for index in offsets.sorted(by: >) { ordered.remove(at: index) }
        let insertion = destination - offsets.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: insertion)
        var iterator = ordered.makeIterator()
        let merged = all.map { item in
            (visible?.contains(item.id) ?? true) ? iterator.next()! : item
        }
        let ranks = Dictionary(uniqueKeysWithValues: merged.enumerated().map { ($0.element.id, $0.offset) })
        var updated = tasks
        for index in updated.indices {
            if let rank = ranks[updated[index].id] { updated[index].order = rank }
        }
        commit(updated)
    }
}
