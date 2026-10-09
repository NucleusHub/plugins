import NotesPluginKit
import NucleusUI
import SwiftUI
@testable import WritingStatsPlugin
import XCTest

@MainActor
final class WritingStatsTests: XCTestCase {
    private func days(_ tz: String = "UTC") -> Days {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz)!
        calendar.firstWeekday = 2
        return Days(calendar: calendar)
    }

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func words(_ n: Int) -> String { Array(repeating: "word", count: n).joined(separator: " ") }

    func testNoteInfo() {
        let body = NoteBody(blocks: [
            Block(.heading2, text: "Plan"),
            Block(.check, text: "Buy milk", checked: true),
            Block(.check, text: "Call Anna"),
            Block(.image, attachment: "x"),
        ])
        let info = NoteInfo(body: body)
        XCTAssertEqual(info.words, 5)
        XCTAssertEqual(info.characters, "PlanBuy milkCall Anna".count)
        XCTAssertEqual(info.readingMinutes, 1)
        XCTAssertEqual(info.checklist.done, 1)
        XCTAssertEqual(info.checklist.total, 2)
        XCTAssertEqual(NoteInfo(body: NoteBody()).readingMinutes, 0)
        XCTAssertEqual(NoteInfo(body: NoteBody(plainText: words(230))).readingMinutes, 1)
        XCTAssertEqual(NoteInfo(body: NoteBody(plainText: words(231))).readingMinutes, 2)
        XCTAssertEqual(NoteInfo(body: NoteBody(plainText: words(1000))).readingMinutes, 5)
    }

    func testLedgerCountsOnlyGrowthAfterThePrimingLook() {
        var ledger = WordLedger()
        ledger.record(["a": 100, "b": 50], day: "2026-10-08")
        XCTAssertTrue(ledger.days.isEmpty)
        ledger.record(["a": 120, "b": 40], day: "2026-10-08")
        ledger.record(["a": 125, "b": 40, "c": 10], day: "2026-10-09")
        ledger.record(["a": 125], day: "2026-10-09") // b and c deleted
        ledger.record(["a": 130, "b": 5], day: "2026-10-09") // b came back
        XCTAssertEqual(ledger.days, ["2026-10-08": 20, "2026-10-09": 25])
        XCTAssertEqual(ledger.words(on: ["2026-10-08", "2026-10-09", "2026-10-10"]), 45)
    }

    func testLedgerKeepsALimitedHistory() {
        var ledger = WordLedger()
        ledger.record([:], day: "x")
        let d = days()
        let start = at("2025-01-01T12:00:00Z")
        for i in 0..<(WordLedger.keptDays + 10) {
            ledger.record(["a": i + 1], day: d.key(d.step(i, from: start)))
        }
        XCTAssertEqual(ledger.days.count, WordLedger.keptDays)
        XCTAssertNil(ledger.days["2025-01-01"])
    }

    func testWeekKeysAcrossDST() {
        // Sunday March 29, 2026 is 23 hours long in Prague.
        let d = days("Europe/Prague")
        XCTAssertEqual(d.weekKeys(through: at("2026-03-29T21:30:00Z")),
                       ["2026-03-23", "2026-03-24", "2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29"])
        XCTAssertEqual(d.weekKeys(through: at("2026-03-23T08:00:00Z")), ["2026-03-23"])
    }

    func testStreakOfEditDays() {
        let d = days("America/New_York")
        // Fall back on Nov 1; evenings in New York are already the next day in UTC.
        let edits: Set = ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02"]
        XCTAssertEqual(d.streak(edits, today: at("2026-11-03T03:00:00Z")), 4) // Nov 2, 22:00
        XCTAssertEqual(d.streak(edits, today: at("2026-11-03T15:00:00Z")), 4) // Nov 3, nothing yet
        XCTAssertEqual(d.streak(edits, today: at("2026-11-04T15:00:00Z")), 0)
    }

    func testSummary() {
        let d = days()
        let now = at("2026-10-09T12:00:00Z") // a Friday
        let notes = [
            note("a", title: "Essay", text: words(900), tags: ["writing", "draft"], created: at("2026-10-05T09:00:00Z")),
            note("b", title: "Groceries", text: words(5), tags: ["home"], created: at("2026-10-08T09:00:00Z"), updated: at("2026-10-09T08:00:00Z")),
            note("c", text: words(40), tags: ["Writing"], created: at("2026-09-28T09:00:00Z")),
            note("d", title: "Old", text: words(1), created: at("2026-01-02T09:00:00Z")),
        ]
        var ledger = WordLedger()
        ledger.record([:], day: "")
        ledger.days = ["2026-10-04": 500, "2026-10-05": 300, "2026-10-07": 50]
        let s = StatsSummary(notes: notes, ledger: ledger, now: now, days: d)
        XCTAssertEqual(s.totalNotes, 4)
        XCTAssertEqual(s.totalWords, 946)
        XCTAssertEqual(s.wordsThisWeek, 350) // Monday the 5th onward
        XCTAssertEqual(s.weeks.count, 14)
        XCTAssertEqual(s.weeks.last?.notes, 2)
        XCTAssertEqual(s.weeks[12].notes, 1)
        XCTAssertEqual(s.weeks.map(\.notes).reduce(0, +), 3) // January is outside the 14 weeks
        XCTAssertEqual(d.key(s.weeks.last!.start), "2026-10-05")
        XCTAssertEqual(d.key(s.weeks.first!.start), "2026-07-06")
        XCTAssertEqual(s.topTags.map(\.tag), ["writing", "draft", "home"])
        XCTAssertEqual(s.topTags.first?.count, 2)
        XCTAssertEqual(s.longest, .init(id: "a", title: "Essay", words: 900))
        XCTAssertEqual(s.streak, 3) // edited the 9th and 8th, words on the 7th, nothing on the 6th
    }

    func testDebouncedUpdatesRecordOnce() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        let store = LedgerStore(fileURL: url)
        let host = MockHost(notes: [note("a", text: words(10))])
        store.record(host.notes)
        host.notes = [note("a", text: words(12))]
        store.notesChanged(host: host, delay: .milliseconds(200))
        host.notes = [note("a", text: words(15))]
        store.notesChanged(host: host, delay: .milliseconds(200))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(store.ledger.days.values.reduce(0, +), 5)
        XCTAssertEqual(LedgerStore(fileURL: url).ledger, store.ledger)
        store.reset()
        XCTAssertEqual(LedgerStore(fileURL: url).ledger, WordLedger())
    }

    func testRendersTheInfoCardAndStatsPage() throws {
        let body = NoteBody(blocks: [
            Block(.heading2, text: "Trip"), Block(.paragraph, text: words(420)),
            Block(.check, text: "Passport", checked: true), Block(.check, text: "Tickets", checked: true), Block(.check, text: "Charger"),
        ])
        let created = Date().addingTimeInterval(-86_400 * 3)
        try snapshot(InfoCard(noteBody: body, created: created, edited: Date(), expanded: .constant(true)).padding(16), name: "writing-stats-info")
        try snapshot(InfoCard(noteBody: body, created: created, edited: Date(), expanded: .constant(false)).padding(16), name: "writing-stats-info-collapsed")

        let d = Days()
        let now = Date()
        var notes: [PluginNote] = []
        let pattern = [1, 3, 2, 0, 4, 2, 5, 3, 1, 6, 4, 2, 7, 3]
        for (week, count) in pattern.enumerated() {
            for i in 0..<count {
                let created = d.step(-(13 - week) * 7 - i, from: now)
                notes.append(note("w\(week)-\(i)", title: "Note \(week)-\(i)", text: words(20 + week * 15 + i * 40),
                                  tags: [["journal"], ["work", "ideas"], ["recipes"], ["work"]][(week + i) % 4], created: created,
                                  updated: d.step(-i, from: now)))
            }
        }
        notes.append(note("long", title: "The long essay on attention", text: words(3240), tags: ["writing"], created: d.step(-40, from: now)))
        var ledger = WordLedger()
        ledger.record([:], day: "")
        for back in 0..<5 { ledger.days[d.key(d.step(-back, from: now))] = 180 + back * 70 }
        try snapshot(SheetShot(title: "Writing statistics") { StatsContent(host: MockHost(notes: notes), ledger: ledger, now: now) },
                     name: "writing-stats-page", background: false)
        try snapshot(NucleusSection { StatsRow(host: MockHost()) }.padding(16), name: "writing-stats-row")
    }
}
