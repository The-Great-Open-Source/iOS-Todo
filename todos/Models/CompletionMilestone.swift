import Foundation

enum CompletionMilestone: Int, CaseIterable {
    case quarter = 25, half = 50, threeQuarters = 75, complete = 100

    var title: String {
        switch self {
        case .quarter: "A great start."
        case .half: "Halfway there!"
        case .threeQuarters: "You’re on a roll."
        case .complete: "All done. Beautifully."
        }
    }

    var headline: String {
        switch self {
        case .quarter: "Nice start!"
        case .half: "Halfway!"
        case .threeQuarters: "Almost there!"
        case .complete: "You did it!"
        }
    }

    var subtitle: String {
        self == .complete ? "Take a breath. You earned it." : "One small win at a time."
    }

    var symbol: String {
        switch self {
        case .quarter: "sparkles"
        case .half: "flame.fill"
        case .threeQuarters: "star.fill"
        case .complete: "trophy.fill"
        }
    }

    /// 1...4. Scales particle counts, haptics, and sound so each tier feels bigger than the last.
    var tier: Int {
        switch self {
        case .quarter: 1
        case .half: 2
        case .threeQuarters: 3
        case .complete: 4
        }
    }

    /// When the "impact" lands: the haptic thump, the confetti, the flash. Everything before it is build-up.
    var impactTime: Double { [0.15, 0.23, 0.29, 0.37][tier - 1] }
    /// How long the medal stays up before it lifts away.
    var holdDuration: Double { [1.6, 1.8, 2.0, 2.8][tier - 1] }
    /// How long the whole effect (including falling confetti) lasts.
    var totalDuration: Double { [2.4, 2.8, 3.2, 4.4][tier - 1] }

    /// If one completion crosses several thresholds, show the highest one.
    static func crossed(before: Int, after: Int, total: Int) -> Self? {
        guard total > 0, before >= 0, after > before, after <= total else { return nil }
        return allCases.last { before * 100 < total * $0.rawValue && after * 100 >= total * $0.rawValue }
    }
}

struct CelebrationEvent: Identifiable {
    let id = UUID()
    let milestone: CompletionMilestone
}

/// Remembers which milestones were already celebrated for each category so reopening and
/// re-completing the same task never replays them, but adding new work starts a fresh run.
struct CelebrationLedger {
    private var celebrated: [String: Set<Int>] = [:]

    /// Returns the milestone to celebrate (if any) and records it, along with every lower one.
    mutating func claim(before: Int, after: Int, total: Int, category: String) -> CompletionMilestone? {
        guard let milestone = CompletionMilestone.crossed(before: before, after: after, total: total),
              !(celebrated[category] ?? []).contains(milestone.rawValue) else { return nil }
        celebrated[category, default: []].formUnion(
            CompletionMilestone.allCases.filter { $0.rawValue <= milestone.rawValue }.map(\.rawValue)
        )
        return milestone
    }

    /// New tasks make the finish line move, so the next run of wins deserves its own cheers.
    mutating func rearm(category: String) { celebrated[category] = nil }

    func hasCelebrated(_ milestone: CompletionMilestone, category: String) -> Bool {
        (celebrated[category] ?? []).contains(milestone.rawValue)
    }
}
