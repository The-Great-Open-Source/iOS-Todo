import Foundation

struct TaskCategory: Identifiable, Hashable, Codable {
    let rawValue: String
    var title: String
    var symbol: String
    var id: String { rawValue }

    static let today = Self(rawValue: "today", title: "Today", symbol: "sun.max")
    // Retained only to migrate existing checklists safely.
    static let work = Self(rawValue: "work", title: "Work", symbol: "briefcase")
    static let personal = Self(rawValue: "personal", title: "Personal", symbol: "house")

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func legacy(_ value: String) -> Self {
        switch value {
        case "today": .today
        case "work": .work
        case "personal": .personal
        default: Self(rawValue: value, title: "Category", symbol: "square.grid.2x2")
        }
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var category: TaskCategory
    var isCompleted = false
    var completedAt: Date?
    var createdAt = Date()
    var order: Int

    func isArchived(at date: Date) -> Bool {
        isCompleted && completedAt.map { date.timeIntervalSince($0) >= 600 } == true
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, category, isCompleted, completedAt, createdAt, order
    }

    init(title: String, category: TaskCategory, order: Int) {
        self.title = title
        self.category = category
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = .legacy(try values.decode(String.self, forKey: .category))
        isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        order = try values.decode(Int.self, forKey: .order)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(category.rawValue, forKey: .category)
        try values.encode(isCompleted, forKey: .isCompleted)
        try values.encodeIfPresent(completedAt, forKey: .completedAt)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(order, forKey: .order)
    }
}
