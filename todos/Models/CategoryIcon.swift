import Foundation

/// Picks an SF Symbol from a category's name, so a new category like "Groceries" gets a cart
/// instead of the same generic icon as every other custom category.
enum CategoryIcon {
    /// Earlier versions gave every custom category this icon. It is replaced when a category is loaded.
    static let legacyDefault = "square.grid.2x2"

    /// First match wins, so more specific entries come first. Stems are matched against the start of each word.
    static let rules: [(symbol: String, stems: [String])] = [
        ("briefcase", ["work", "job", "office", "career", "business", "client", "meeting", "boss"]),
        ("graduationcap", ["study", "school", "class", "learn", "course", "homework", "exam", "uni", "college", "lecture", "assignment", "thesis"]),
        ("cart", ["shop", "grocer", "buy", "market", "supermarket", "purchase"]),
        ("fork.knife", ["food", "cook", "meal", "recipe", "dinner", "lunch", "breakfast", "restaurant", "eat", "kitchen", "bake"]),
        ("cup.and.saucer", ["coffee", "cafe", "tea"]),
        ("dumbbell", ["gym", "workout", "exercise", "fitness", "lift", "strength", "train"]),
        ("figure.run", ["run", "jog", "marathon", "sport", "cardio", "walk", "hike"]),
        ("bicycle", ["bike", "cycl"]),
        ("pills", ["med", "pill", "vitamin", "supplement", "prescription"]),
        ("cross.case", ["doctor", "dentist", "clinic", "hospital", "medical", "appointment", "checkup"]),
        ("heart", ["health", "wellness", "self", "love", "relationship", "wellbeing", "romance", "date"]),
        ("brain.head.profile", ["mind", "meditat", "mental", "therapy", "journal", "mindful"]),
        ("moon", ["night", "evening", "bedtime", "sleep"]),
        ("book", ["read", "book", "novel", "library", "article"]),
        ("creditcard", ["bill", "payment", "finance", "bank", "budget", "tax", "money", "invoice", "debt", "loan", "rent", "expense"]),
        ("chart.line.uptrend.xyaxis", ["invest", "saving", "stock", "crypto", "growth", "metric"]),
        ("airplane", ["travel", "trip", "flight", "vacation", "holiday", "tour", "visa", "abroad", "passport"]),
        ("car", ["car", "drive", "vehicle", "garage", "auto", "commute"]),
        ("house", ["home", "house", "household", "chore", "apartment", "clean", "laundry", "decor"]),
        ("figure.2.and.child.holdinghands", ["family", "kid", "child", "baby", "parent"]),
        ("person.2", ["friend", "social", "people", "team", "community", "network"]),
        ("pawprint", ["pet", "dog", "cat", "puppy", "kitten", "vet"]),
        ("gift", ["gift", "birthday", "party", "wedding", "celebrat", "present", "event", "anniversary"]),
        ("lightbulb", ["idea", "brainstorm", "think", "someday", "maybe", "inspir"]),
        ("chevron.left.forwardslash.chevron.right", ["code", "coding", "dev", "program", "software", "app", "website", "tech", "bug"]),
        ("paintbrush", ["design", "art", "draw", "creative", "paint", "sketch", "craft"]),
        ("hammer", ["project", "build", "diy", "repair", "fix", "maintenance", "tool"]),
        ("target", ["goal", "focus", "habit", "resolution", "aim", "objective"]),
        ("flag", ["priority", "urgent", "important", "deadline", "asap"]),
        ("music.note", ["music", "song", "guitar", "piano", "band", "sing", "playlist"]),
        ("camera", ["photo", "camera", "picture"]),
        ("film", ["movie", "film", "watch", "show", "series", "netflix", "video", "tv"]),
        ("gamecontroller", ["game", "gaming", "play", "console"]),
        ("leaf", ["garden", "plant", "nature", "outdoor", "eco", "green"]),
        ("envelope", ["email", "mail", "message", "letter", "reply"]),
        ("phone", ["call", "phone", "contact"]),
        ("calendar", ["schedule", "calendar", "plan", "weekly", "daily", "routine", "week", "month"]),
        ("tshirt", ["cloth", "wardrobe", "fashion", "outfit", "style"]),
        ("globe", ["world", "language", "news", "global", "web"]),
        ("star", ["favorite", "favourite", "best", "wish", "special"]),
        ("tray", ["inbox", "misc", "other", "general", "random", "later", "backlog", "stuff"]),
    ]

    private static let neutral = ["bookmark", "tag", "folder", "star", "flag", "heart"]

    static func suggest(for title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for rule in rules {
            if words.contains(where: { word in rule.stems.contains { word.hasPrefix($0) } }) { return rule.symbol }
        }
        // No keyword: a letter badge, so every category still looks distinct and none shares a default.
        if let first = words.first?.first {
            if first.isASCII, first.isLetter { return "\(first).circle" }
            if first.isASCII, first.isNumber { return "\(first).circle" }
        }
        // Names in other scripts get a stable neutral icon derived from the name.
        var hash: UInt32 = 2166136261
        for byte in folded.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return neutral[Int(hash % UInt32(neutral.count))]
    }
}
