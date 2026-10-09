import Foundation
import NotesPluginKit

/// The numbers in a note's Info card.
public struct NoteInfo: Equatable, Sendable {
    public static let wordsPerMinute = 230

    public let words: Int
    public let characters: Int
    /// Whole minutes, at least 1 once there's a word.
    public let readingMinutes: Int
    public let checklist: (done: Int, total: Int)

    public init(body: NoteBody, title: String = "") {
        words = body.wordCount
        characters = body.plainText.filter { !$0.isNewline }.count
        readingMinutes = words == 0 ? 0 : max(1, Int((Double(words) / Double(Self.wordsPerMinute)).rounded(.up)))
        checklist = body.checklistProgress
    }

    public static func == (a: NoteInfo, b: NoteInfo) -> Bool {
        a.words == b.words && a.characters == b.characters && a.readingMinutes == b.readingMinutes
            && a.checklist.done == b.checklist.done && a.checklist.total == b.checklist.total
    }
}

/// Day keys (`yyyy-MM-dd`) and day steps in the person's calendar; DST days count as one day.
public struct Days: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func step(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Days in a row in `days`, ending today, or yesterday while today is still open.
    public func streak(_ days: Set<String>, today: Date) -> Int {
        var cursor = days.contains(key(today)) ? today : step(-1, from: today)
        var count = 0
        while days.contains(key(cursor)) {
            count += 1
            cursor = step(-1, from: cursor)
        }
        return count
    }

    /// The start of the week holding `date` (the calendar's first weekday).
    public func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Keys of the days from the week's start through `date`.
    public func weekKeys(through date: Date) -> [String] {
        var keys: [String] = []
        var cursor = weekStart(date)
        let end = key(date)
        while keys.count < 7 {
            let k = key(cursor)
            keys.append(k)
            if k == end { break }
            cursor = step(1, from: cursor)
        }
        return keys
    }
}

/// Words added per day, kept on the device: the last word count of each note and what each day added.
public struct WordLedger: Codable, Equatable, Sendable {
    public static let keptDays = 400

    public var counts: [String: Int] = [:]
    public var days: [String: Int] = [:]
    /// The first look only takes the counts, so notes that were there before don't count as written today.
    public var primed = false

    public init() {}

    /// Adds today's growth: each note's words over its last count (a new note counts whole). Deleted words don't subtract.
    public mutating func record(_ current: [String: Int], day: String) {
        defer { counts = current }
        guard primed else { primed = true; return }
        let added = current.reduce(0) { sum, entry in sum + max(0, entry.value - (counts[entry.key] ?? 0)) }
        if added > 0 { days[day, default: 0] += added }
        if days.count > Self.keptDays {
            for old in days.keys.sorted().prefix(days.count - Self.keptDays) { days[old] = nil }
        }
    }

    public func words(on keys: [String]) -> Int { keys.reduce(0) { $0 + (days[$1] ?? 0) } }
}

/// Everything on the statistics page.
public struct StatsSummary: Sendable {
    public struct Week: Identifiable, Equatable, Sendable {
        public let start: Date
        public let notes: Int
        public var id: Date { start }
    }

    public struct Longest: Equatable, Sendable {
        public let id: String
        public let title: String
        public let words: Int
    }

    public static let weekCount = 14

    public let totalNotes: Int
    public let totalWords: Int
    public let wordsThisWeek: Int
    /// Oldest first, the current week last.
    public let weeks: [Week]
    public let topTags: [(tag: String, count: Int)]
    public let longest: Longest?
    /// Days in a row with an edit.
    public let streak: Int

    public init(notes: [PluginNote], ledger: WordLedger, now: Date = Date(), days: Days = Days()) {
        let counted = notes.map { ($0, $0.body.wordCount) }
        totalNotes = notes.count
        totalWords = counted.reduce(0) { $0 + $1.1 }
        wordsThisWeek = ledger.words(on: days.weekKeys(through: now))

        let thisWeek = days.weekStart(now)
        let starts = (0..<Self.weekCount).reversed().map {
            days.calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) ?? thisWeek
        }
        var perWeek: [Date: Int] = [:]
        for note in notes { perWeek[days.weekStart(note.createdAt), default: 0] += 1 }
        weeks = starts.map { Week(start: $0, notes: perWeek[$0] ?? 0) }

        var tagCounts: [String: Int] = [:]
        for note in notes { for tag in Set(note.tags.map { $0.lowercased() }) { tagCounts[tag, default: 0] += 1 } }
        topTags = tagCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(6).map { ($0.key, $0.value) }

        longest = counted.filter { $0.1 > 0 }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id > $1.0.id }
            .map { Longest(id: $0.0.id, title: $0.0.displayTitle ?? String(localized: "Untitled note"), words: $0.1) }

        var edited = Set(ledger.days.filter { $0.value > 0 }.keys)
        for note in notes {
            edited.insert(days.key(note.updatedAt))
            edited.insert(days.key(note.createdAt))
        }
        streak = days.streak(edited, today: now)
    }
}
