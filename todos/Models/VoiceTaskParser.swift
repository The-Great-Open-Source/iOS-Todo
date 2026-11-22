import Foundation

/// A sentence turned into a task: a clean title plus whatever the speaker said about when, where, and how important.
struct VoiceTask: Equatable {
    var title: String
    /// When to remind. Nil when no time was mentioned, or the time had already passed.
    var due: Date?
    /// False when only a day was said (for example "tomorrow"), so a default morning time was filled in.
    var hasSpokenTime: Bool
    var category: TaskCategory?
    var isStarred: Bool
}

/// Understands everyday phrasing such as "I have to wash my clothes today evening near 5pm", on the device and
/// without any network: it finds the day and time, the list it belongs in, and whether it is important, and
/// leaves behind just the action as the title.
enum VoiceTaskParser {
    static let defaultMorningHour = 9
    private static let dayParts: [String: Int] = ["morning": 9, "afternoon": 15, "evening": 18, "night": 20]
    private static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8,
                                 "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                      "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]

    static func parse(_ text: String, now: Date = Date(), categories: [TaskCategory] = [], calendar: Calendar = .current) -> VoiceTask {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var work = " " + original + " "
        let weekdayNames = weekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let monthNames = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"

        // Spoken numbers next to a time or a duration become digits: "five pm" -> "5 pm".
        let words = numberWords.keys.joined(separator: "|")
        replaceAll(in: &work, pattern: "\\b(\(words))\\b(?=\\s*(?:am|pm|a\\.m\\.|p\\.m\\.|o'?clock|minutes?|mins?|hours?|hrs?|days?|weeks?))") { groups in
            " \(numberWords[groups[0].lowercased()] ?? 0)"
        }
        replaceAll(in: &work, pattern: "\\bhalf an hour\\b") { _ in "30 minutes" }
        replaceAll(in: &work, pattern: "\\b(?:an|one) hour\\b") { _ in "1 hour" }

        var dayOffset: Int?
        var weekday: (number: Int, forceNext: Bool)?
        var monthDay: (month: Int, day: Int)?
        var relative: Date?
        var part: String?
        var hour: Int?
        var minute = 0
        var meridiem: String?

        // "in 2 hours", "in 30 minutes", "in 3 days", "in 2 weeks"
        if let m = firstMatch(in: &work, pattern: "\\bin\\s+(\\d{1,3})\\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\\b"), let amount = Int(m[0]) {
            let unit = m[1].lowercased()
            if unit.hasPrefix("min") { relative = now.addingTimeInterval(Double(amount) * 60) }
            else if unit.hasPrefix("h") { relative = now.addingTimeInterval(Double(amount) * 3600) }
            else if unit.hasPrefix("d") { dayOffset = amount }
            else { dayOffset = amount * 7 }
        }

        // "5th of december", "december 5th"
        if let m = firstMatch(in: &work, pattern: "\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?(\(monthNames))\\b"),
           let day = Int(m[0]), let month = months[String(m[1].lowercased().prefix(3))], (1...31).contains(day) {
            monthDay = (month, day)
        } else if let m = firstMatch(in: &work, pattern: "\\b(?:on\\s+)?(\(monthNames))\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b"),
                  let day = Int(m[1]), let month = months[String(m[0].lowercased().prefix(3))], (1...31).contains(day) {
            monthDay = (month, day)
        }

        // A part of the day, only when something marks it as a time ("this evening", "tomorrow morning", "in the evening").
        // The day word is put back so it is read just after.
        if let m = firstMatch(in: &work, pattern: "\\btonight\\b", keepText: " today ") { _ = m; part = "night" }
        if part == nil, let m = firstMatch(in: &work,
            pattern: "\\b(?:(today|tomorrow|tmrw|\(weekdayNames))\\s+(?:in\\s+the\\s+|during\\s+the\\s+)?|(this|in\\s+the|during\\s+the|by|near|around|late|early)\\s+)(morning|afternoon|evening|night)\\b",
            keepWith: { groups in groups[0].isEmpty ? (groups[1].lowercased() == "this" ? " today " : " ") : " \(groups[0]) " }) {
            part = m[2].lowercased()
        }

        // Day words.
        if firstMatch(in: &work, pattern: "\\bday after tomorrow\\b") != nil { dayOffset = 2 }
        else if firstMatch(in: &work, pattern: "\\b(?:tomorrow|tmrw)\\b") != nil { dayOffset = 1 }
        else if firstMatch(in: &work, pattern: "\\btoday\\b") != nil { dayOffset = 0 }
        else if let m = firstMatch(in: &work, pattern: "\\b(?:(next|this|on|by)\\s+)?(\(weekdayNames))\\b"), let number = weekdays[m[1].lowercased()] {
            weekday = (number, m[0].lowercased() == "next")
        } else if firstMatch(in: &work, pattern: "\\bnext week\\b") != nil { weekday = (2, true) }
        else if firstMatch(in: &work, pattern: "\\b(?:this\\s+)?weekend\\b") != nil { weekday = (7, false) }

        // Clock times: "5pm", "5:30 pm", "17:00", "5 o'clock", "noon".
        if let m = firstMatch(in: &work, pattern: "\\b(?:(?:at|by|near|around|about|before|until|till|@)\\s+)?(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm|a\\.m\\.|p\\.m\\.)(?![a-z])"), let h = Int(m[0]) {
            hour = h; minute = Int(m[1]) ?? 0; meridiem = m[2].lowercased().hasPrefix("a") ? "am" : "pm"
        } else if let m = firstMatch(in: &work, pattern: "\\b(?:(?:at|by|near|around|about|before|until|till)\\s+)?(\\d{1,2}):(\\d{2})\\b"), let h = Int(m[0]), h < 24 {
            hour = h; minute = Int(m[1]) ?? 0
        } else if let m = firstMatch(in: &work, pattern: "\\b(?:(?:at|by|near|around|about)\\s+)?(\\d{1,2})\\s*o'?clock\\b"), let h = Int(m[0]) {
            hour = h
        } else if firstMatch(in: &work, pattern: "\\b(?:at\\s+|by\\s+|around\\s+)?noon\\b") != nil {
            hour = 12; meridiem = "pm"
        } else if let m = firstMatch(in: &work, pattern: "\\b(?:at|by|near|around|about)\\s+(\\d{1,2})\\b(?!\\s*[:%.]|\\s*(?:kg|km|min|items|people|st|nd|rd|th))"), let h = Int(m[0]), (1...12).contains(h) {
            hour = h
        }
        // A day-part word left over beside a time ("evening ... 5") still tells morning from evening.
        if part == nil, hour != nil,
           let m = firstMatch(in: &work, pattern: "\\b(morning|afternoon|evening|night)\\b") { part = m[0].lowercased() }

        // Importance.
        var starred = false
        let starPatterns = ["(?:(?:this|it)\\s+(?:is|'s)\\s+|it's\\s+)?(?:very\\s+|really\\s+|super\\s+)?(?:important|urgent)(?:ly)?",
                            "\\bhigh priority\\b", "\\btop priority\\b", "\\basap\\b", "\\bdon'?t forget\\b(?!\\s+to)"]
        for pattern in starPatterns where firstMatch(in: &work, pattern: pattern) != nil { starred = true }

        // A category named out loud: "add it to work", "in my shopping list".
        var category: TaskCategory?
        let candidates = categories.filter { $0.id != TaskCategory.today.id }.sorted { $0.title.count > $1.title.count }
        for candidate in candidates {
            let name = NSRegularExpression.escapedPattern(for: candidate.title.lowercased())
            let explicit = "\\b(?:(?:add|put|save|file|move)(?:\\s+(?:it|this|that))?\\s+)?(?:to|in|into|under|on)\\s+(?:my\\s+|the\\s+)?\(name)(?:\\s+(?:list|category|tab|folder))?\\b"
            if firstMatch(in: &work, pattern: explicit) != nil { category = candidate; break }
        }
        if category == nil {
            for candidate in candidates {
                let name = NSRegularExpression.escapedPattern(for: candidate.title.lowercased())
                if work.range(of: "\\b\(name)\\s+(?:list|category|tab)\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                    replaceAll(in: &work, pattern: "\\b(?:my\\s+|the\\s+)?\(name)\\s+(?:list|category|tab)\\b") { _ in " " }
                    category = candidate; break
                }
            }
        }

        // When.
        var due: Date?
        var spokenTime = hour != nil || part != nil || relative != nil
        let start = calendar.startOfDay(for: now)
        if let relative { due = relative }
        else {
            var resolvedHour = hour, resolvedMinute = minute
            if let h = hour {
                if let meridiem {
                    resolvedHour = meridiem == "pm" ? (h % 12) + 12 : h % 12
                } else if h >= 13 || h == 0 {
                    resolvedHour = h
                } else if let part {
                    resolvedHour = part == "morning" ? h % 12 : (h % 12) + 12
                } else {
                    resolvedHour = nil // decided below, once the day is known
                }
            } else if let part {
                resolvedHour = dayParts[part]; resolvedMinute = 0
            }
            var day: Date?
            if let monthDay {
                var parts = calendar.dateComponents([.year], from: now)
                parts.month = monthDay.month; parts.day = monthDay.day
                if var candidate = calendar.date(from: parts) {
                    if candidate < start { candidate = calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate }
                    day = candidate
                }
            } else if let dayOffset {
                day = calendar.date(byAdding: .day, value: dayOffset, to: start)
            } else if let weekday {
                day = nextWeekday(weekday.number, from: start, strictlyAfter: weekday.forceNext, calendar: calendar)
            }
            let explicitDay = day != nil
            if day == nil, spokenTime { day = start }
            if let day {
                if resolvedHour == nil, let h = hour {
                    // "at 5" with no am or pm: pick the nearest sensible one.
                    let morning = calendar.date(bySettingHour: h % 12, minute: minute, second: 0, of: day)
                    if calendar.isDate(day, inSameDayAs: now) {
                        resolvedHour = (morning.map { $0 > now } ?? false) ? h % 12 : (h % 12) + 12
                    } else {
                        resolvedHour = h <= 6 || h == 12 ? (h % 12) + 12 : h
                    }
                }
                let finalHour = resolvedHour ?? defaultMorningHour
                spokenTime = resolvedHour != nil
                if !spokenTime, dayOffset == 0 { due = nil }
                else if var candidate = calendar.date(bySettingHour: finalHour, minute: resolvedHour != nil ? resolvedMinute : 0, second: 0, of: day) {
                    if candidate <= now, !explicitDay { candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate }
                    due = candidate > now ? candidate : nil
                }
            }
        }

        let title = cleanTitle(work, fallback: original)
        return VoiceTask(title: title, due: due, hasSpokenTime: due != nil && spokenTime, category: category, isStarred: starred)
    }

    // MARK: Title

    private static let leadIns = [
        "(?:hey|hi|ok|okay|so|um|uh|well|please|kindly)\\b[,.]?", "(?:can|could|would|will) you\\b", "i(?:'ll| will| would like| want| need| have got| have| had| should| must| gotta|'ve got| 've| am going)? to\\b",
        "i(?:'d| would) like to\\b", "i (?:need|want|have) to\\b", "i(?:'ve| have) got to\\b", "(?:we|you) (?:need|have|got) to\\b", "(?:need|have|has|got|want|ought) to\\b", "gotta\\b", "wanna\\b",
        "remind me (?:to|about)\\b", "remember to\\b", "(?:don't|do not) forget to\\b", "add (?:a |an |the )?(?:new )?(?:task|todo|to-do|reminder|item)(?: to| for| that| about| called| named)?\\b",
        "(?:create|make|set|put) (?:a |an |the )?(?:new )?(?:task|todo|to-do|reminder)(?: to| for| that| about| called| named)?\\b", "task\\b[:,]?", "reminder\\b[:,]?", "to\\b", "that i\\b", "i\\b",
    ]

    private static func cleanTitle(_ text: String, fallback: String) -> String {
        var title = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for lead in leadIns {
                if let range = title.range(of: "^(?:\(lead))\\s*", options: [.regularExpression, .caseInsensitive]), range.upperBound > title.startIndex {
                    title.removeSubrange(range); changed = true; break
                }
            }
            // Words left dangling where the time or day used to be.
            if let range = title.range(of: "(?:^|\\s)(?:at|by|on|in|near|around|about|for|this|the|and|then|before|after|until|till|from|of|during|every|tonight|today|tomorrow)[\\s,.;:!?]*$", options: [.regularExpression, .caseInsensitive]) {
                title.removeSubrange(range); changed = true
            }
            if let range = title.range(of: "^[\\s,.;:!?-]+|[\\s,;:-]+$", options: .regularExpression) {
                title.removeSubrange(range); changed = true
            }
        }
        title = title.replacingOccurrences(of: "\\s+([,.!?])", with: "$1", options: .regularExpression)
        if title.hasSuffix(".") { title.removeLast() }
        guard !title.isEmpty else {
            return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    // MARK: Helpers

    private static func nextWeekday(_ weekday: Int, from start: Date, strictlyAfter: Bool, calendar: Calendar) -> Date? {
        let today = calendar.component(.weekday, from: start)
        var delta = (weekday - today + 7) % 7
        if delta == 0 && strictlyAfter { delta = 7 }
        return calendar.date(byAdding: .day, value: delta, to: start)
    }

    /// Finds the first match, replaces it with a space (or `keep`), and returns its capture groups (empty string when unmatched).
    @discardableResult
    private static func firstMatch(in text: inout String, pattern: String, keepText: String = " ") -> [String]? {
        firstMatch(in: &text, pattern: pattern, keepWith: { _ in keepText })
    }

    @discardableResult
    private static func firstMatch(in text: inout String, pattern: String, keepWith keep: ([String]) -> String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let groups = (1..<max(match.numberOfRanges, 1)).map { index -> String in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        text.replaceSubrange(range, with: keep(groups))
        return groups
    }

    private static func replaceAll(in text: inout String, pattern: String, with replacement: ([String]) -> String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let groups = (1..<max(match.numberOfRanges, 1)).map { index -> String in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            text.replaceSubrange(range, with: replacement(groups))
        }
    }
}
