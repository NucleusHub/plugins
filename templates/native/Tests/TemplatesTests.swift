import NotesPluginKit
import NucleusUI
import SwiftUI
@testable import TemplatesPlugin
import XCTest

@MainActor
final class TemplatesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // Friday, October 9, 2026, 14:05 UTC.
    private let friday = Date(timeIntervalSince1970: 1_791_554_700)

    private func filler(_ locale: String, firstWeekday: Int = 2, tz: TimeZone? = nil) -> PlaceholderFiller {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return PlaceholderFiller(locale: Locale(identifier: locale), calendar: calendar, timeZone: tz ?? utc)
    }

    func testFillsDateInTheLocale() {
        XCTAssertEqual(filler("en_US").fill("Meeting · {{date}}", on: friday), "Meeting · October 9, 2026")
        XCTAssertEqual(filler("cs_CZ").fill("{{date}}", on: friday), "9. října 2026")
        XCTAssertEqual(filler("en_US").fill("{{weekday}}", on: friday), "Friday")
        XCTAssertEqual(filler("en_US").fill("{{month}}", on: friday), "October 2026")
        XCTAssertEqual(filler("en_US").fill("{{year}}", on: friday), "2026")
    }

    func testTimeFollowsTheTimeZone() {
        XCTAssertEqual(filler("en_US").fill("{{time}}", on: friday), "2:05\u{202F}PM")
        XCTAssertEqual(filler("en_GB", tz: TimeZone(identifier: "Europe/Prague")).fill("{{time}}", on: friday), "16:05")
        // Late evening in UTC is already the next day in Tokyo.
        let late = Date(timeIntervalSince1970: 1_791_590_400) // Oct 10 00:00 UTC
        XCTAssertEqual(filler("en_US", tz: TimeZone(identifier: "America/Los_Angeles")).fill("{{date}}", on: late), "October 9, 2026")
        XCTAssertEqual(filler("en_US", tz: TimeZone(identifier: "Asia/Tokyo")).fill("{{date}}", on: late), "October 10, 2026")
    }

    func testWeekAndDaysOfTheWeek() {
        XCTAssertEqual(filler("en_US").fill("Week {{week}}", on: friday), "Week 41")
        XCTAssertEqual(filler("en_US").fill("{{day:1}} – {{day:7}}", on: friday), "Monday, Oct 5 – Sunday, Oct 11")
        // A Sunday-first calendar starts the week on the 4th.
        XCTAssertEqual(filler("en_US", firstWeekday: 1).fill("{{day:1}}", on: friday), "Sunday, Oct 4")
        XCTAssertEqual(filler("en_US").fill("{{tomorrow}}", on: friday), "Saturday, October 10")
    }

    func testUnknownAndBrokenPlaceholdersStay() {
        let f = filler("en_US")
        XCTAssertEqual(f.fill("{{name}} and {{day:9}}", on: friday), "{{name}} and {{day:9}}")
        XCTAssertEqual(f.fill("Open {{date", on: friday), "Open {{date")
        XCTAssertEqual(f.fill("{{ DATE }}!", on: friday), "October 9, 2026!")
        XCTAssertEqual(f.fill("No braces", on: friday), "No braces")
    }

    func testDraftFillsTitleAndBodyAndKeepsColor() throws {
        let meeting = try XCTUnwrap(NoteTemplate.builtIn.first { $0.id == "builtin.meeting" })
        let draft = meeting.draft(on: friday, filler: filler("en_US"), folderID: "f1")
        XCTAssertEqual(draft.title, "Meeting · October 9, 2026")
        XCTAssertEqual(draft.body.blocks.first?.text, "Friday, 2:05\u{202F}PM")
        XCTAssertEqual(draft.color, .tint("indigo"))
        XCTAssertEqual(draft.folderID, "f1")
        XCTAssertFalse(draft.body.plainText.contains("{{"))
    }

    func testEveryBuiltInIsComplete() {
        XCTAssertEqual(NoteTemplate.builtIn.count, 8)
        XCTAssertEqual(Set(NoteTemplate.builtIn.map(\.id)).count, 8)
        for template in NoteTemplate.builtIn {
            XCTAssertTrue(template.isBuiltIn)
            XCTAssertNotNil(template.color, template.name)
            XCTAssertTrue(template.body.blocks.contains { $0.type == .heading2 || $0.type == .heading3 }, template.name)
            let draft = template.draft(on: friday, filler: filler("en_US"))
            XCTAssertFalse(draft.title.contains("{{"), template.name)
            XCTAssertFalse(draft.body.blocks.map(\.text).joined().contains("{{"), template.name)
        }
    }

    func testTemplateFromNoteDropsAttachmentsAndKeepsColor() {
        let body = NoteBody(blocks: [
            Block(.heading2, text: "Standup {{date}}"),
            Block(.image, attachment: "a1"),
            Block(.check, text: "Yesterday", checked: true),
            Block(.divider),
            Block(.file, attachment: "a2"),
        ])
        let source = note("n1", title: "Standup", body: body, color: .tint("teal"))
        let template = NoteTemplate.from(note: source, name: "  Daily standup ")
        XCTAssertEqual(template.name, "Daily standup")
        XCTAssertEqual(template.title, "Standup")
        XCTAssertEqual(template.color, .tint("teal"))
        XCTAssertEqual(template.body.blocks.map(\.type), [.heading2, .check, .divider])
        XCTAssertTrue(template.body.blocks[1].checked)
        XCTAssertFalse(template.isBuiltIn)
        XCTAssertEqual(NoteTemplate.from(note: source, name: " ").name, "Standup")
    }

    func testStoreSavesAndDeletes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("templates-\(UUID().uuidString)/t.json")
        let store = TemplateStore(fileURL: url)
        XCTAssertTrue(store.templates.isEmpty)
        let a = NoteTemplate(name: "A", title: "A", body: NoteBody(plainText: "{{date}}"), color: .hex("FF0000"))
        let b = NoteTemplate(name: "B", title: "B", body: NoteBody(plainText: "b"))
        store.add(a)
        store.add(b)
        XCTAssertEqual(TemplateStore(fileURL: url).templates.map(\.name), ["B", "A"])
        XCTAssertEqual(TemplateStore(fileURL: url).templates.last?.color, .hex("FF0000"))
        store.delete(id: b.id)
        XCTAssertEqual(TemplateStore(fileURL: url).templates.map(\.name), ["A"])
        store.removeAll()
        XCTAssertTrue(TemplateStore(fileURL: url).templates.isEmpty)
    }

    func testPickingATemplateFinishesWithItsDraft() {
        var finished: PluginNoteDraft??
        let context = NewNoteContext(host: MockHost(), folderID: "f2") { finished = $0 }
        let draft = NoteTemplate.builtIn[3].draft(folderID: context.folderID)
        context.finish(draft)
        XCTAssertEqual(finished??.title, "Packing list")
        XCTAssertEqual(finished??.folderID, "f2")
    }

    func testRendersTheTemplateGrid() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("templates-shot-\(UUID().uuidString).json")
        let store = TemplateStore(fileURL: url)
        store.add(NoteTemplate(name: "Standup", icon: "square.on.square.fill", title: "Standup", body: NoteBody(blocks: [
            Block(.heading2, text: "Yesterday"), Block(.check, text: "Shipped the editor"), Block(.heading2, text: "Today"), Block(.check, text: ""),
        ]), color: .tint("teal")))
        let host = MockHost()
        try snapshot(SheetShot(title: "New from template") { TemplatesGrid(context: NewNoteContext(host: host, folderID: nil), store: store) }, name: "templates-grid", background: false)

        let empty = TemplateStore(fileURL: url.appendingPathExtension("empty"))
        try snapshot(SheetShot(title: "New from template") { TemplatesGrid(context: NewNoteContext(host: host, folderID: nil), store: empty) }, name: "templates-grid-empty", background: false)

        let source = note("n1", title: "Weekly review", body: NoteBody(blocks: [
            Block(.heading2, text: "Wins"), Block(.bullet, text: "Launched Notes"), Block(.heading2, text: "Next week"), Block(.check, text: ""),
        ]), color: .tint("pink"))
        try snapshot(SheetShot(title: "Save as template", confirm: "Save") { SaveTemplateSheet(context: NoteActionContext(note: source, host: host), store: empty).form }, name: "templates-save", background: false)
    }
}
