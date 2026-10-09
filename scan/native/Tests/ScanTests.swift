@testable import ScanPlugin
import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit
import XCTest

final class ScanTextsTests: XCTestCase {
    func testCodingRoundTrip() {
        let texts = ["a1": "Invoice 42", "a2": "Total 1 200 Kč"]
        XCTAssertEqual(ScanTexts.decode(ScanTexts.encode(texts)), texts)
        XCTAssertNil(ScanTexts.encode([:]))
        XCTAssertEqual(ScanTexts.decode(.object(["a": .number(1), "b": "ok"])), ["b": "ok"])
        XCTAssertEqual(ScanTexts.decode(nil), [:])
    }

    func testSearchTextFollowsBodyOrderAndSkipsRemovedPages() {
        let body = NoteBody(blocks: [Block(.image, attachment: "p2"), Block(text: "between"), Block(.image, attachment: "p1")])
        let data: [String: JSONValue] = ["scan": ScanTexts.encode(["p1": "first page", "p2": "second page", "gone": "old"])!]
        let n = note("n", title: "Scan", body: body, pluginData: data)
        XCTAssertEqual(ScanTexts.searchText(for: n), "second page\nfirst page")
        XCTAssertEqual(ScanDetail().searchText(for: n), "second page\nfirst page")
        XCTAssertNil(ScanTexts.searchText(for: note("e", title: "Empty")))
    }

    func testPrunedKeepsOnlyPagesInTheBody() {
        let body = NoteBody(blocks: [Block(.image, attachment: "p1")])
        XCTAssertEqual(ScanTexts.pruned(["p1": "a", "p2": "b"], body: body), ["p1": "a"])
        XCTAssertNil(ScanTexts.pruned(["p1": "a"], body: body))
    }

    func testCleanAndBlocks() {
        XCTAssertEqual(ScanTexts.clean(["  Receipt ", "", "  ", "Total: 12"]), "Receipt\nTotal: 12")
        XCTAssertEqual(ScanTexts.blocks(for: "a\nb").map(\.text), ["a", "b"])
    }

    func testFittedSize() {
        XCTAssertEqual(ScanTexts.fitted(CGSize(width: 3024, height: 4032)), CGSize(width: 1920, height: 2560))
        XCTAssertEqual(ScanTexts.fitted(CGSize(width: 1000, height: 800)), CGSize(width: 1000, height: 800))
    }

    func testTitle() {
        let date = Date(timeIntervalSince1970: 1_791_590_400) // 2026-10-10 UTC
        XCTAssertTrue(ScanTexts.title(for: date, locale: Locale(identifier: "en_US")).hasPrefix("Scan Oct"))
    }

    func testRecognizesRenderedText() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 300)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
            ("Invoice number 2048" as NSString).draw(at: CGPoint(x: 40, y: 110), withAttributes: [.font: UIFont.systemFont(ofSize: 56)])
        }
        let text = await Scanner.recognize(try XCTUnwrap(image.cgImage))
        XCTAssertTrue(text.contains("2048"), "got \(text)")
    }
}

@MainActor
final class ScanFlowTests: XCTestCase {
    func testInsertStoresTextsInPluginData() async {
        let current = note("n", title: "Receipts")
        let host = FakeHost(notes: [current])
        var inserted: [Block] = []
        let context = InsertContext(note: current, host: host, insert: { inserted += $0 }, append: { _ in })
        await ScanInsertAction().insert([ScannedPage(jpeg: Data([1]), text: "Total 12"), ScannedPage(jpeg: Data([2]), text: "")], context)
        XCTAssertEqual(inserted.map(\.type), [.image, .image])
        let texts = ScanTexts.decode(host.pluginData["n"]?["scan"] ?? nil)
        XCTAssertEqual(texts[inserted[0].attachment!], "Total 12")
        XCTAssertEqual(PendingScans.shared.texts[inserted[0].attachment!], "Total 12")
    }

    func testHiddenNoteGetsTextInTheBodyNotPluginData() async {
        let current = note("h", title: "Secret", hidden: true)
        let host = FakeHost(notes: [current])
        var inserted: [Block] = []
        let context = InsertContext(note: current, host: host, insert: { inserted += $0 }, append: { _ in })
        await ScanInsertAction().insert([ScannedPage(jpeg: Data([1]), text: "PIN 1234\nKeep safe")], context)
        XCTAssertEqual(inserted.map(\.text), ["", "PIN 1234", "Keep safe"])
        XCTAssertNil(host.pluginData["h"])
    }

    func testNewNoteDraft() async {
        let host = FakeHost()
        var draft: PluginNoteDraft?
        let context = NewNoteContext(host: host, folderID: "f", finish: { draft = $0 })
        await ScanNewNote().finish([ScannedPage(jpeg: Data([1]), text: "Lease")], context)
        XCTAssertEqual(draft?.folderID, "f")
        XCTAssertTrue(draft?.title.hasPrefix("Scan ") ?? false)
        let id = draft?.body.attachmentIDs.first
        XCTAssertNotNil(id)
        XCTAssertEqual(ScanTexts.decode(draft?.pluginData["scan"])[id!], "Lease")
    }
}

@MainActor
final class ScanSnapshots: XCTestCase {
    func testScannedTextSection() throws {
        let host = FakeHost()
        let page = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            UIColor(white: 0.55, alpha: 1).setFill()
            for row in 0..<12 { ctx.fill(CGRect(x: 30, y: 40 + row * 28, width: row % 3 == 2 ? 150 : 240, height: 9)) }
        }
        let attachment = Attachment(id: "p1", name: "Scan 1.jpg", contentType: "image/jpeg", size: 1, sha256: "", kind: .image)
        host.stored["p1"] = page.jpegData(compressionQuality: 0.9)
        let body = NoteBody(blocks: [Block(.image, attachment: "p1"), Block(.image, attachment: "p2")])
        let texts = ["p1": "RENTAL AGREEMENT\nThis agreement is made between Jana Nováková (landlord) and Petr Svoboda (tenant) for the flat at Vinohradská 12, Praha 2.\nRent: 18 500 Kč per month, due on the 5th.\nDeposit: two months' rent.",
                     "p2": "Signed in Prague on 1 October 2026."]
        let n = note("n", title: "Lease", body: body, attachments: [attachment])
        try snapshot("plugin-scan-scanned-text") {
            ScannedTextSection(note: n, host: host, noteBody: .constant(body), value: .constant(ScanTexts.encode(texts)))
                .padding(16)
                .background(NucleusBackground())
        }
        try snapshot("plugin-scan-reading", height: 500) { ReadingText(done: 1, total: 3) }
    }
}
