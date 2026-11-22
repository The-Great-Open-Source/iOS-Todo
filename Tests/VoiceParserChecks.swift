import Foundation

/// Checks that spoken sentences turn into the right title, time, list, and star.
enum VoiceParserChecks {
    static func run() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Sunday 22 November 2026, 14:00.
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 14, minute: 0))!
        let shopping = TaskCategory(rawValue: "shop", title: "Shopping", symbol: "cart")
        let categories = [TaskCategory.today, .work, .personal, shopping]

        func parse(_ text: String) -> VoiceTask { VoiceTaskParser.parse(text, now: now, categories: categories, calendar: calendar) }
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        func expect(_ text: String, title: String, due: Date?, spoken: Bool? = nil, category: TaskCategory? = nil, starred: Bool = false,
                    line: UInt = #line) {
            let result = parse(text)
            precondition(result.title == title, "title for “\(text)”: got “\(result.title)”, wanted “\(title)”", line: line)
            precondition(result.due == due, "due for “\(text)”: got \(String(describing: result.due)), wanted \(String(describing: due))", line: line)
            if let spoken { precondition(result.hasSpokenTime == spoken, "spoken time for “\(text)”", line: line) }
            precondition(result.category == category, "category for “\(text)”: got \(String(describing: result.category?.title))", line: line)
            precondition(result.isStarred == starred, "star for “\(text)”", line: line)
        }

        // The example from the request.
        expect("I have to wash my clothes today evening near 5pm", title: "Wash my clothes", due: at(22, 17), spoken: true)
        expect("I have to wash my clothes today evening near 5 PM.", title: "Wash my clothes", due: at(22, 17))
        expect("wash my clothes this evening", title: "Wash my clothes", due: at(22, 18))
        expect("call mom tonight", title: "Call mom", due: at(22, 20))
        expect("call mom tomorrow morning", title: "Call mom", due: at(23, 9))
        expect("tomorrow at 8:30 am submit the report", title: "Submit the report", due: at(23, 8, 30))
        expect("remind me to pay the electricity bill tomorrow at 5 pm", title: "Pay the electricity bill", due: at(23, 17))
        expect("buy milk tomorrow", title: "Buy milk", due: at(23, 9), spoken: false)
        expect("I need to send the invoice on friday", title: "Send the invoice", due: at(27, 9), spoken: false)
        expect("dentist next monday at 10am", title: "Dentist", due: at(23, 10))
        expect("water the plants in 2 hours", title: "Water the plants", due: at(22, 16), spoken: true)
        expect("stretch in half an hour", title: "Stretch", due: at(22, 14, 30))
        expect("book tickets on 5th december at 9 am", title: "Book tickets", due: at(5, 9, month: 12))
        expect("anniversary dinner december 25", title: "Anniversary dinner", due: at(25, 9, month: 12), spoken: false)
        expect("pick up the parcel at noon tomorrow", title: "Pick up the parcel", due: at(23, 12))
        expect("meeting five pm tomorrow", title: "Meeting", due: at(23, 17))
        expect("gym at 6 tomorrow evening", title: "Gym", due: at(23, 18))
        expect("take medicine at 9 tomorrow morning", title: "Take medicine", due: at(23, 9))

        // No time said: no reminder, and the sentence is left alone.
        expect("buy bread", title: "Buy bread", due: nil)
        expect("clean the kitchen today", title: "Clean the kitchen", due: nil)
        // A bare hour picks the next sensible one, and a time that already passed today does not become a reminder.
        expect("call the bank at 5", title: "Call the bank", due: at(22, 17))
        expect("call the bank at 7 am today", title: "Call the bank", due: nil)
        expect("call the bank at 9 am", title: "Call the bank", due: at(23, 9))
        // Numbers that are not times stay in the title.
        expect("buy 2 apples", title: "Buy 2 apples", due: nil)
        expect("read chapter 5 tomorrow", title: "Read chapter 5", due: at(23, 9))
        // “evening” by itself is just part of the task.
        expect("go for an evening walk", title: "Go for an evening walk", due: nil)

        // Importance and lists.
        expect("it's urgent, renew my passport tomorrow at 3pm", title: "Renew my passport", due: at(23, 15), starred: true)
        expect("buy milk and eggs, add it to shopping", title: "Buy milk and eggs", due: nil, category: shopping)
        expect("finish the slides in my work list tomorrow at 11 am", title: "Finish the slides", due: at(23, 11), category: .work)
        expect("buy detergent", title: "Buy detergent", due: nil)
        expect("send the work report", title: "Send the work report", due: nil)
        expect("add a task to call grandma on saturday at 4 pm, high priority", title: "Call grandma", due: at(28, 16), starred: true)

        // Never an empty title.
        precondition(!parse("tomorrow at 5 pm").title.isEmpty)
        print("PASS: voice sentences become a title, time, list, and star")
    }
}
