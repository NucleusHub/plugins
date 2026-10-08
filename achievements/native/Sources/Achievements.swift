import Foundation
import NucleusUI
import TodoPluginKit

/// Badges for things worth celebrating, with progress toward each.
struct Achievement: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let icon: String
    let tint: NucleusTint
    let target: Int
    /// A plugin the achievement is about; it's hidden while that plugin is off.
    var needs: String?

    /// What counts toward an achievement, from the tasks and a few device counters.
    struct Facts {
        var done = 0
        var streak = 0
        var bestStreak = 0
        var focusMinutes = 0
        var onTime = 0
        var lists = 0
        var tags = 0
        var places = 0
        var earlyBird = false
        var nightOwl = false
        var inboxZero = false
        var perfectDays = 0
        var subtasksDone = 0

        init() {}

        init(tasks: [PluginTask], stats: PluginStats, lists: Int, perfectDays: Int) {
            let cal = Calendar.current
            done = stats.doneTotal
            streak = stats.streak
            bestStreak = max(stats.bestStreak, stats.streak)
            focusMinutes = stats.focusMinutes
            onTime = tasks.compactMap(\.onTime).filter { $0 }.count
            self.lists = lists
            tags = Set(tasks.flatMap(\.tags).map { $0.lowercased() }).count
            places = tasks.filter { $0.location != nil }.count
            let hours = tasks.compactMap(\.completedAt).map { cal.component(.hour, from: $0) }
            earlyBird = hours.contains { $0 < 7 && $0 >= 4 }
            nightOwl = hours.contains { $0 >= 23 || $0 < 3 }
            inboxZero = done >= 10 && !tasks.contains { !$0.done && $0.listID == nil }
            self.perfectDays = perfectDays
            subtasksDone = tasks.reduce(0) { $0 + $1.subtasksDone }
        }
    }

    func progress(_ f: Facts) -> Int {
        switch id {
        case "first", "ten", "century", "fiveHundred": f.done
        case "streak3", "streak7", "streak30": f.bestStreak
        case "focus1h", "focus10h": f.focusMinutes
        case "punctual": f.onTime
        case "organiser": f.lists
        case "tagger": f.tags
        case "explorer": f.places
        case "earlyBird": f.earlyBird ? 1 : 0
        case "nightOwl": f.nightOwl ? 1 : 0
        case "inboxZero": f.inboxZero ? 1 : 0
        case "perfectDay": f.perfectDays
        case "stepper": f.subtasksDone
        default: 0
        }
    }

    @MainActor
    static func available(_ host: any TodoHost) -> [Achievement] {
        all.filter { $0.needs.map(host.isActive) ?? true }
    }

    static let all: [Achievement] = [
        .init(id: "first", title: "First step", detail: "Finish your first task.", icon: "checkmark", tint: .emerald, target: 1),
        .init(id: "ten", title: "Getting going", detail: "Finish 10 tasks.", icon: "bolt.fill", tint: .amber, target: 10),
        .init(id: "century", title: "Century", detail: "Finish 100 tasks.", icon: "rosette", tint: .violet, target: 100),
        .init(id: "fiveHundred", title: "Unstoppable", detail: "Finish 500 tasks.", icon: "crown.fill", tint: .orange, target: 500),
        .init(id: "streak3", title: "On a roll", detail: "Get something done 3 days in a row.", icon: "flame.fill", tint: .orange, target: 3),
        .init(id: "streak7", title: "Week warrior", detail: "Keep a 7-day streak.", icon: "flame.circle.fill", tint: .rose, target: 7),
        .init(id: "streak30", title: "Habit forged", detail: "Keep a 30-day streak.", icon: "medal.fill", tint: .pink, target: 30),
        .init(id: "perfectDay", title: "Perfect day", detail: "Finish everything due on a day.", icon: "sun.max.fill", tint: .amber, target: 1),
        .init(id: "punctual", title: "Punctual", detail: "Meet 10 deadlines on time.", icon: "target", tint: .teal, target: 10),
        .init(id: "focus1h", title: "Deep work", detail: "Focus for an hour in total.", icon: "timer", tint: .indigo, target: 60),
        .init(id: "focus10h", title: "In the zone", detail: "Focus for 10 hours in total.", icon: "brain.head.profile", tint: .violet, target: 600),
        .init(id: "earlyBird", title: "Early bird", detail: "Finish a task before 7 in the morning.", icon: "sunrise.fill", tint: .sky, target: 1),
        .init(id: "nightOwl", title: "Night owl", detail: "Finish a task after 11 at night.", icon: "moon.stars.fill", tint: .indigo, target: 1),
        .init(id: "inboxZero", title: "Inbox zero", detail: "Empty your Inbox after finishing 10 tasks.", icon: "tray", tint: .sky, target: 1),
        .init(id: "organiser", title: "Organiser", detail: "Make 5 lists.", icon: "folder.fill", tint: .blue, target: 5),
        .init(id: "tagger", title: "Tagger", detail: "Use 5 different tags.", icon: "number", tint: .slate, target: 5),
        .init(id: "explorer", title: "Explorer", detail: "Give a task a place.", icon: "map.fill", tint: .teal, target: 1, needs: "places"),
        .init(id: "stepper", title: "Step by step", detail: "Tick off 25 steps.", icon: "checklist", tint: .emerald, target: 25),
    ]
}

/// Which achievements are unlocked on this device and when; announces new ones.
@MainActor
@Observable
final class Achievements {
    static let shared = Achievements()

    private(set) var unlocked: [String: Date]
    private(set) var facts = Achievement.Facts()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// The first check after launch (or after the plugin is turned on) unlocks without fanfare.
    @ObservationIgnored private var primed = false
    /// When the day-done confetti last played, so an unlock at the same moment doesn't play it again.
    @ObservationIgnored private var celebratedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: "achievements") as? [String: Double] ?? [:]
        unlocked = stored.mapValues { Date(timeIntervalSince1970: $0) }
    }

    var perfectDays: Int { defaults.integer(forKey: "perfectDays") }

    func dayCompleted(host: any TodoHost) {
        celebratedAt = Date()
        defaults.set(perfectDays + 1, forKey: "perfectDays")
        update(host: host)
    }

    /// Checks right away the first time, so a page showing progress isn't empty.
    func prime(host: any TodoHost) {
        if !primed { update(host: host) }
    }

    /// Re-checks a moment after the tasks change.
    func update(host: any TodoHost) {
        let quietly = !primed
        primed = true
        pending?.cancel()
        pending = Task { [weak host] in
            try? await Task.sleep(for: .milliseconds(quietly ? 0 : 700))
            guard !Task.isCancelled, let host else { return }
            facts = Achievement.Facts(tasks: host.tasks, stats: host.stats, lists: host.listCount, perfectDays: perfectDays)
            var fresh: [Achievement] = []
            for a in Achievement.available(host) where unlocked[a.id] == nil && a.progress(facts) >= a.target {
                unlocked[a.id] = Date()
                fresh.append(a)
            }
            guard !fresh.isEmpty else { return }
            defaults.set(unlocked.mapValues { $0.timeIntervalSince1970 }, forKey: "achievements")
            guard !quietly else { return }
            let alreadyCheering = celebratedAt.map { Date().timeIntervalSince($0) < 4 } ?? false
            if !alreadyCheering {
                host.cheer()
                host.playSuccess()
            }
            for a in fresh {
                host.show(String(localized: "Achievement unlocked: \(String(localized: a.title))"), icon: "trophy.fill")
            }
        }
    }

    func reset() {
        unlocked = [:]
        defaults.removeObject(forKey: "achievements")
        defaults.removeObject(forKey: "perfectDays")
    }
}
