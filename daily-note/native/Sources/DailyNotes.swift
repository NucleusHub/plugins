import Foundation
import NotesPluginKit

/// Calendar days as `yyyy-MM-dd` keys in the person's calendar, and streaks over them.
/// Days are counted with calendar arithmetic, never 86 400 s, so DST days of 23 or 25 hours count as one.
public struct DayMath: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func key(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The start of the day a key names, in this calendar.
    public func date(for key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public func day(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    /// Days in a row with an entry, ending today, or yesterday while today is still open.
    public func streak(days: Set<String>, today: Date) -> Int {
        var cursor = days.contains(key(for: today)) ? today : day(-1, from: today)
        var count = 0
        while days.contains(key(for: cursor)) {
            count += 1
            cursor = day(-1, from: cursor)
        }
        return count
    }

    /// Monday to Sunday of the week holding `date`.
    public func week(containing date: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let fromMonday = (weekday + 5) % 7
        let monday = day(-fromMonday, from: date)
        return (0..<7).map { day($0, from: monday) }
    }
}

/// What makes a note a daily note, and the draft for a new one.
public enum DailyNotes {
    public static let pluginID = "daily-note"
    public static let folderName = "Journal"
    public static let tag = "journal"

    /// The day a note is the daily note of, from its plugin data `{"date": "yyyy-MM-dd"}`.
    public static func dayKey(of note: PluginNote) -> String? {
        guard let key = note.pluginData[pluginID]?["date"]?.string, key.count == 10 else { return nil }
        return key
    }

    public static func days(in notes: [PluginNote]) -> Set<String> {
        Set(notes.compactMap(dayKey))
    }

    /// The daily note for a day; the most recently edited when a sync brought in two.
    public static func note(for key: String, in notes: [PluginNote]) -> PluginNote? {
        notes.filter { dayKey(of: $0) == key }.max { $0.updatedAt < $1.updatedAt }
    }

    /// The Journal folder when the person has one. The host can't make folders, so without it the note is tagged #journal.
    public static func journalFolder(in folders: [PluginFolder]) -> PluginFolder? {
        folders.first { !$0.hidden && $0.name.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(folderName) == .orderedSame }
    }

    public static func title(for date: Date, math: DayMath, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: math.calendar, timeZone: math.calendar.timeZone)
            .weekday(.wide).month(.wide).day().year())
    }

    public static func draft(for date: Date, folders: [PluginFolder], math: DayMath, locale: Locale = .autoupdatingCurrent) -> PluginNoteDraft {
        PluginNoteDraft(title: title(for: date, math: math, locale: locale), body: NoteBody(blocks: [Block(.paragraph, text: "")]),
                        folderID: journalFolder(in: folders)?.id, color: .tint("amber"), tags: [tag],
                        pluginData: [pluginID: .object(["date": .string(math.key(for: date))])])
    }

    /// Opens today's note, making it first when there's none.
    @MainActor
    public static func openToday(host: any NotesHost, now: Date = Date(), math: DayMath = DayMath()) {
        if let existing = note(for: math.key(for: now), in: host.notes) {
            host.open(noteID: existing.id)
        } else if let id = host.create(draft(for: now, folders: host.folders, math: math)) {
            host.open(noteID: id)
        }
    }
}
