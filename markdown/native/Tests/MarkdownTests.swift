@testable import MarkdownPlugin
import NotesPluginKit
import NucleusUI
import SwiftUI
import XCTest

@MainActor
final class MarkdownTests: XCTestCase {
    func testFileNamesAreSanitized() {
        XCTAssertEqual(MarkdownFile.fileName(for: "Groceries"), "Groceries.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "Q3: plan / budget?"), "Q3 plan budget.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "  ..hidden  "), "hidden.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "Ends with dots..."), "Ends with dots.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "Line\nbreak\ttab"), "Line break tab.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "<>|*"), "Untitled note.md")
        XCTAssertEqual(MarkdownFile.fileName(for: ""), "Untitled note.md")
        XCTAssertEqual(MarkdownFile.fileName(for: "Café · Plán 🎉"), "Café · Plán 🎉.md")
        let long = MarkdownFile.fileName(for: String(repeating: "word ", count: 40))
        XCTAssertLessThanOrEqual(long.count, MarkdownFile.maxNameLength + 3)
        XCTAssertFalse(long.dropLast(3).hasSuffix(" "))
    }

    func testExportPutsTheTitleOnTop() {
        let body = NoteBody(blocks: [Block(.check, text: "Milk", checked: true), Block(.image, attachment: "abc")])
        XCTAssertEqual(MarkdownFile.export(title: "Shopping", body: body), "# Shopping\n\n- [x] Milk\n\n![](attachment:abc)\n")
        XCTAssertEqual(MarkdownFile.export(title: " ", body: NoteBody(plainText: "Hi")), "Hi\n")
        XCTAssertEqual(MarkdownFile.export(title: "Only", body: NoteBody()), "# Only\n\n")
    }

    func testImportTakesTheTitleFromTheFirstHeading() {
        let draft = MarkdownFile.draft(text: "# Trip\r\n\r\n- [ ] Passport\r\n- [x] Tickets\r\n", fileName: "notes.md")
        XCTAssertEqual(draft.title, "Trip")
        XCTAssertEqual(draft.body.blocks.map(\.type), [.check, .check])
        XCTAssertTrue(draft.body.blocks[1].checked)
    }

    func testImportFallsBackToTheFileNameAndReadsFrontMatter() {
        XCTAssertEqual(MarkdownFile.draft(text: "Some **bold** text", fileName: "My idea.markdown").title, "My idea")
        let front = MarkdownFile.draft(text: "---\ntitle: \"Weekly sync\"\ntags: [a]\n---\n# Agenda\n- one", fileName: "x.md")
        XCTAssertEqual(front.title, "Weekly sync")
        XCTAssertEqual(front.body.blocks.first?.type, .heading1)
        XCTAssertEqual(front.body.blocks.first?.text, "Agenda")
    }

    func testTextFilesStayPlain() {
        let draft = MarkdownFile.draft(text: "\n\n# not a heading\n- not a list", fileName: "log.TXT")
        XCTAssertEqual(draft.title, "log")
        XCTAssertEqual(draft.body.blocks.map(\.type), [.paragraph, .paragraph])
        XCTAssertEqual(draft.body.blocks.first?.text, "# not a heading")
        XCTAssertEqual(MarkdownFile.blocks(text: "# Head\nline", fileName: "a.md").map(\.type), [.heading1, .paragraph])
    }

    func testDecodesCommonEncodings() {
        XCTAssertEqual(MarkdownFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data("Ahoj".utf8)), "Ahoj")
        XCTAssertEqual(MarkdownFile.decode("Žluťoučký".data(using: .utf16)!), "Žluťoučký")
        XCTAssertEqual(MarkdownFile.decode(Data([0x43, 0x61, 0x66, 0xE9])), "Café") // Latin 1, not UTF-8
    }

    func testExportedFileKeepsItsName() throws {
        let url = try XCTUnwrap(Exporter.write("# Hi\n", named: "Hi there.md"))
        XCTAssertEqual(url.lastPathComponent, "Hi there.md")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Hi\n")
    }

    func testImportingSeveralFilesCreatesNotes() {
        let host = MockHost()
        var finished: PluginNoteDraft?? = .none
        let context = NewNoteContext(host: host, folderID: "f") { finished = $0 }
        ImportAsNotes.importFiles([ImportedFile(name: "a.md", text: "# A"), ImportedFile(name: "b.txt", text: "B")], context: context)
        XCTAssertEqual(host.created.map(\.title), ["A", "b"])
        XCTAssertEqual(host.created.map(\.folderID), ["f", "f"])
        XCTAssertEqual(host.toasts, ["Imported 2 notes"])
        XCTAssertEqual(finished, .some(nil))

        ImportAsNotes.importFiles([ImportedFile(name: "c.md", text: "text")], context: context)
        XCTAssertEqual(host.created.count, 2)
        XCTAssertEqual(finished??.title, "c")
    }

    func testRendersTheSheets() throws {
        let body = NoteBody(blocks: [
            Block(.heading2, text: "Agenda"),
            Block(.numbered, text: "Roadmap review"),
            Block(.numbered, text: "Hiring"),
            Block(.heading2, text: "Action items"),
            Block(.check, text: "Send the deck", checked: true),
            Block(.check, text: "Book the room"),
            Block(.quote, text: "Ship small, ship often."),
            Block(.image, attachment: "6f1c2a"),
        ])
        let context = NoteActionContext(note: note("n", title: "Team sync: Q4", body: body), host: MockHost())
        try snapshot(SheetShot(title: "Export as Markdown") { ExportSheet(context: context).content }, name: "markdown-export", background: false)
        let sheet = ImportSheet(title: "Import Markdown", message: "Pick Markdown or text files; each one becomes a note.", multiple: true,
                                onCancel: {}, onFiles: { _ in })
        try snapshot(SheetShot(title: "Import Markdown") { sheet.content }, name: "markdown-import", background: false)
    }
}
