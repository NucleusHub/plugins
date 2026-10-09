@testable import DailyNotePlugin
import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI
import XCTest

@MainActor
final class DailyNoteTests: XCTestCase {
    private func math(_ tz: String) -> DayMath {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        return DayMath(calendar: calendar)
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func daily(_ key: String, id: String? = nil, words: String = "", updated: Date = Date()) -> PluginNote {
        note(id ?? key, title: key, text: words, updated: updated, pluginData: ["daily-note": .object(["date": .string(key)])])
    }

    func testKeysFollowTheTimeZone() {
        let instant = at("2026-10-10T02:30:00Z")
        XCTAssertEqual(math("UTC").key(for: instant), "2026-10-10")
        XCTAssertEqual(math("America/Los_Angeles").key(for: instant), "2026-10-09")
        XCTAssertEqual(math("Asia/Tokyo").key(for: instant), "2026-10-10")
        XCTAssertEqual(math("Pacific/Kiritimati").key(for: at("2026-12-31T10:30:00Z")), "2027-01-01")
    }

    func testKeyRoundTripsToTheStartOfTheDay() throws {
        let m = math("Europe/Prague")
        let start = try XCTUnwrap(m.date(for: "2026-03-29"))
        XCTAssertEqual(start, at("2026-03-28T23:00:00Z"))
        XCTAssertEqual(m.key(for: start), "2026-03-29")
        XCTAssertNil(m.date(for: "nope"))
    }

    func testStreakAcrossSpringForward() {
        // March 8, 2026 has 23 hours in New York.
        let m = math("America/New_York")
        let days: Set = ["2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"]
        XCTAssertEqual(m.streak(days: days, today: at("2026-03-10T03:30:00Z")), 4) // still the 9th in New York
        XCTAssertEqual(m.streak(days: days, today: at("2026-03-10T23:30:00Z")), 5)
    }

    func testStreakAcrossFallBack() {
        // November 1, 2026 has 25 hours in New York; late on the 1st must still step back one day at a time.
        let m = math("America/New_York")
        let days: Set = ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"]
        XCTAssertEqual(m.streak(days: days, today: at("2026-11-02T04:30:00Z")), 3) // 23:30 on Nov 1
        XCTAssertEqual(m.streak(days: days, today: at("2026-11-02T15:00:00Z")), 4)
    }

    func testStreakWaitsForTodayAndBreaksOnAGap() {
        let m = math("UTC")
        let today = at("2026-10-09T12:00:00Z")
        XCTAssertEqual(m.streak(days: [], today: today), 0)
        XCTAssertEqual(m.streak(days: ["2026-10-08", "2026-10-07"], today: today), 2)
        XCTAssertEqual(m.streak(days: ["2026-10-09", "2026-10-07"], today: today), 1)
        XCTAssertEqual(m.streak(days: ["2026-10-07"], today: today), 0)
        XCTAssertEqual(m.streak(days: ["2026-12-31", "2027-01-01"], today: at("2027-01-01T08:00:00Z")), 2)
    }

    func testWeekRunsMondayToSundayEvenOverDST() {
        let m = math("Europe/Prague")
        // Sunday March 29, 2026 is the spring-forward day in Prague.
        let week = m.week(containing: at("2026-03-29T20:00:00Z")).map(m.key)
        XCTAssertEqual(week, ["2026-03-23", "2026-03-24", "2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29"])
        let monday = m.week(containing: at("2026-10-05T00:10:00+02:00")).map(m.key)
        XCTAssertEqual(monday.first, "2026-10-05")
        XCTAssertEqual(monday.last, "2026-10-11")
    }

    func testFindsTheDailyNoteForADay() {
        let notes = [
            note("plain", title: "Groceries"),
            daily("2026-10-08"),
            daily("2026-10-09", id: "old", updated: at("2026-10-09T07:00:00Z")),
            daily("2026-10-09", id: "new", updated: at("2026-10-09T09:00:00Z")),
        ]
        XCTAssertEqual(DailyNotes.note(for: "2026-10-09", in: notes)?.id, "new")
        XCTAssertNil(DailyNotes.note(for: "2026-10-10", in: notes))
        XCTAssertEqual(DailyNotes.days(in: notes), ["2026-10-08", "2026-10-09"])
        XCTAssertNil(DailyNotes.dayKey(of: note("x", pluginData: ["daily-note": .object(["date": .number(3)])])))
    }

    func testDraftUsesTheJournalFolderOrTheTag() {
        let m = math("UTC")
        let day = at("2026-10-09T12:00:00Z")
        let none = DailyNotes.draft(for: day, folders: [PluginFolder(id: "f1", name: "Work", icon: "folder", tint: "blue")], math: m,
                                    locale: Locale(identifier: "en_US"))
        XCTAssertNil(none.folderID)
        XCTAssertEqual(none.tags, ["journal"])
        XCTAssertEqual(none.title, "Friday, October 9, 2026")
        XCTAssertEqual(none.pluginData["daily-note"]?["date"]?.string, "2026-10-09")

        let folders = [PluginFolder(id: "h", name: "Journal", icon: "lock", tint: "slate", hidden: true),
                       PluginFolder(id: "j", name: " journal ", icon: "book", tint: "amber")]
        XCTAssertEqual(DailyNotes.draft(for: day, folders: folders, math: m).folderID, "j")
    }

    func testOpenTodayCreatesOnceThenOpens() {
        let host = MockHost()
        let now = Date()
        DailyNotes.openToday(host: host, now: now)
        XCTAssertEqual(host.created.count, 1)
        XCTAssertEqual(host.opened, ["new1"])
        DailyNotes.openToday(host: host, now: now)
        XCTAssertEqual(host.created.count, 1)
        XCTAssertEqual(host.opened, ["new1", "new1"])
    }

    func testJournalSmartFolderMatchesDailyNotes() throws {
        let registrar = PluginRegistrarProbe()
        let folder = try XCTUnwrap(registrar.journal)
        XCTAssertTrue(folder.contains(daily("2026-10-09")))
        XCTAssertFalse(folder.contains(note("x", title: "Not daily")))
    }

    func testRendersTheHomeCard() throws {
        let m = DayMath()
        let now = Date()
        let keys = [-6, -5, -3, -2, -1, 0].map { m.key(for: m.day($0, from: now)) }
        let host = MockHost(notes: keys.map { daily($0, words: "A short note about the day with a few words in it") })
        try snapshot(DailyHomeCard(host: host, now: now).padding(16), name: "daily-note-home")
        try snapshot(DailyHomeCard(host: MockHost(), now: now).padding(16), name: "daily-note-home-empty")
    }
}

/// Reads the smart folder the plugin registers.
@MainActor
private struct PluginRegistrarProbe {
    var journal: SmartFolderDefinition?

    init() {
        let registry = PluginRegistry(app: "notes", state: InMemoryPluginStateStore())
        _ = registry.install(DailyNotePlugin())
        journal = registry.contributions(to: .smartFolders).first?.value
    }
}
