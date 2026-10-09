@testable import BacklinksPlugin
import NotesPluginKit
import NucleusUI
import SwiftUI
import XCTest

private func linkBody(_ text: String, to id: String, before: String = "See ") -> NoteBody {
    NoteBody(blocks: [Block(.paragraph, runs: [Run(before), Run(text, link: NoteLink.url(for: id))])])
}

final class NoteLinkTests: XCTestCase {
    func testRoundTrip() {
        XCTAssertEqual(NoteLink.noteID(in: NoteLink.url(for: "abc123")), "abc123")
        XCTAssertEqual(NoteLink.noteID(in: "com.nucleushome.notes://note/abc?x=1"), "abc")
        XCTAssertNil(NoteLink.noteID(in: "https://example.com/note/abc"))
        XCTAssertNil(NoteLink.noteID(in: "com.nucleushome.notes://note/"))
        XCTAssertNil(NoteLink.noteID(in: nil))
    }
}

final class BacklinkIndexTests: XCTestCase {
    func testIndexesLinksNewestFirstOncePerSource() {
        let target = note("t", title: "Target")
        var twice = linkBody("Target", to: "t")
        twice.blocks.append(Block(.paragraph, runs: [Run("again", link: NoteLink.url(for: "t"))]))
        let a = note("a", title: "A", body: twice, updated: 10)
        let b = note("b", title: "B", body: linkBody("Target", to: "t"), updated: 20)
        let unrelated = note("c", title: "C", body: NoteBody(plainText: "Target"))
        let index = BacklinkIndex(notes: [target, a, b, unrelated])
        XCTAssertEqual(index.backlinks(to: target).map(\.id), ["b", "a"])
        XCTAssertEqual(index.backlinks(to: target).first?.context, "See Target")
        XCTAssertTrue(index.backlinks(to: a).isEmpty)
    }

    func testSelfLinksDontCount() {
        let me = note("m", title: "Me", body: linkBody("Me", to: "m"))
        XCTAssertTrue(BacklinkIndex(notes: [me]).backlinks(to: me).isEmpty)
    }

    func testHiddenSourcesOnlyShowOnHiddenNotes() {
        let open = note("o", title: "Open")
        let vaulted = note("v", title: "Vaulted", hidden: true)
        let secret = note("s", title: "Secret", body: NoteBody(blocks: [
            Block(.paragraph, runs: [Run("x", link: NoteLink.url(for: "o")), Run("y", link: NoteLink.url(for: "v"))]),
        ]), hidden: true)
        let index = BacklinkIndex(notes: [open, vaulted, secret])
        XCTAssertTrue(index.backlinks(to: open).isEmpty)
        XCTAssertEqual(index.backlinks(to: vaulted).map(\.id), ["s"])
    }

    func testBuildsTwoThousandNotesQuickly() {
        let notes = (0..<2000).map { i in note("n\(i)", title: "Note \(i)", body: linkBody("Note \(i / 2)", to: "n\(i / 2)")) }
        let start = Date()
        let index = BacklinkIndex(notes: notes)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertEqual(index.backlinks(to: "n10", includeHidden: false).map(\.id).sorted(), ["n20", "n21"])
    }

    @MainActor
    func testIndexerDebouncesAndPublishesSnapshot() async throws {
        let indexer = BacklinkIndexer(delay: .milliseconds(50))
        let target = note("t", title: "T")
        indexer.notesChanged([target])
        indexer.notesChanged([target, note("a", title: "A", body: linkBody("T", to: "t"))])
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(indexer.index?.backlinks(to: target).map(\.id), ["a"])
        XCTAssertEqual(BacklinkSnapshot.shared.index?.backlinks(to: target).count, 1)
        XCTAssertEqual(BacklinksDetail().chip(for: target), NoteChip(icon: "arrow.uturn.left", text: "1"))
        indexer.reset()
        XCTAssertNil(BacklinksDetail().chip(for: target))
    }
}

final class WikiLinksTests: XCTestCase {
    let notes = [
        note("cafe", title: "Café plans", updated: 5),
        note("cafe-old", title: "cafe plans", updated: 1),
        note("shop", title: "Shopping", updated: 3),
        note("shop2", title: "shopping", updated: 9),
    ]

    func testFindsTitlesOncePerFoldedTitle() {
        let body = NoteBody(plainText: "Go to [[Café plans]] and [[ cafe PLANS ]]\n[[Shopping]] [[]] [[open")
        XCTAssertEqual(WikiLinks.titles(in: body), ["Café plans", "Shopping"])
    }

    func testResolvePrefersExactThenNewestFolded() {
        let ids = WikiLinks.resolve(["Café plans", "CAFE PLANS", "Shopping", "SHOPPING", "Nope"], in: notes)
        // "Café plans" exactly; then "cafe plans" folded — the same key, the exact one stays.
        XCTAssertEqual(ids[NoteSearch.fold("Café plans")], "cafe")
        XCTAssertEqual(ids[NoteSearch.fold("Shopping")], "shop")
        XCTAssertNil(ids[NoteSearch.fold("Nope")])
        XCTAssertEqual(WikiLinks.resolve(["SHOPPING"], in: notes)[NoteSearch.fold("shopping")], "shop2")
    }

    func testApplyKeepsMarksAndSkipsCodeAndLinks() {
        let body = NoteBody(blocks: [
            Block(.bullet, runs: [Run("Buy "), Run("[[Shop", bold: true), Run("ping]] now")]),
            Block(.paragraph, runs: [Run("[[Shopping]]", code: true), Run(" [[Shopping]]", link: "https://x")]),
            Block(.code, runs: [Run("[[Shopping]]")]),
            Block(.paragraph, runs: [Run("[[Unknown]] stays")]),
        ])
        let (out, count) = WikiLinks.apply(body, ids: [NoteSearch.fold("shopping"): "shop"])
        XCTAssertEqual(count, 1)
        XCTAssertEqual(out.blocks[0].runs, [Run("Buy "), Run("Shopping", bold: true, link: NoteLink.url(for: "shop")), Run(" now")])
        XCTAssertEqual(out.blocks[1], body.blocks[1])
        XCTAssertEqual(out.blocks[2], body.blocks[2])
        XCTAssertEqual(out.blocks[3].text, "[[Unknown]] stays")
    }

    func testDiacriticsAndCaseInBody() {
        let body = NoteBody(plainText: "Viz [[CAFE plans]], [[Café Plans]].")
        let ids = WikiLinks.resolve(WikiLinks.titles(in: body), in: notes)
        let (out, count) = WikiLinks.apply(body, ids: ids)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(out.blocks[0].runs.compactMap(\.link), [NoteLink.url(for: "cafe"), NoteLink.url(for: "cafe")])
        XCTAssertEqual(out.blocks[0].text, "Viz CAFE plans, Café Plans.")
    }

    @MainActor
    func testConvertActionCreatesMissingNotes() async {
        let current = note("cur", title: "Today", body: NoteBody(plainText: "[[Shopping]] and [[New idea]]"))
        let host = FakeHost(notes: notes + [current])
        host.confirmAnswer = 0
        await ConvertLinksAction().perform(NoteActionContext(note: current, host: host))
        XCTAssertEqual(host.created.map(\.title), ["New idea"])
        let links = host.updates.first?.body?.blocks[0].runs.compactMap(\.link)
        XCTAssertEqual(links, [NoteLink.url(for: "shop"), NoteLink.url(for: "new1")])
        XCTAssertEqual(host.toasts, ["Linked 2 notes"])
    }

    @MainActor
    func testConvertActionLinksExistingOnly() async {
        let current = note("cur", title: "Today", body: NoteBody(plainText: "[[Shopping]] and [[New idea]]"))
        let host = FakeHost(notes: notes + [current])
        host.confirmAnswer = 1
        await ConvertLinksAction().perform(NoteActionContext(note: current, host: host))
        XCTAssertTrue(host.created.isEmpty)
        XCTAssertEqual(host.updates.first?.body?.blocks[0].text, "Shopping and [[New idea]]")
    }

    @MainActor
    func testPickerFilter() {
        let current = note("cur", title: "Today")
        let all = notes + [current, note("h", title: "Hidden shopping", hidden: true)]
        XCTAssertEqual(NotePicker.filter(all, query: "shop", current: current).shown.map(\.id), ["shop2", "shop"])
        XCTAssertEqual(NotePicker.filter(all, query: "CAFE pl", current: current).shown.map(\.id), ["cafe", "cafe-old"])
        XCTAssertEqual(NotePicker.filter(all, query: "", current: current, limit: 2).total, 4)
    }
}

@MainActor
final class BacklinksSnapshots: XCTestCase {
    func testLinkedFromSection() throws {
        let target = note("t", title: "Trip to Lisbon")
        let notes = [
            target,
            note("a", title: "Packing list", body: linkBody("Trip to Lisbon", to: "t", before: "Everything for the "), updated: -600),
            note("b", title: "Budget 2026", body: linkBody("Trip to Lisbon", to: "t", before: "Flights and hotel for "), updated: -86_400 * 2),
            note("c", title: "Restaurants to try", body: linkBody("Lisbon", to: "t", before: "Pastéis de nata places for the trip — "), updated: -86_400 * 9),
        ].map { $0 }
        let host = FakeHost(notes: notes)
        BacklinkIndexer.shared.reset()
        try snapshot("plugin-backlinks-linked-from") {
            LinkedFromSection(note: target, host: host)
                .padding(16)
                .background(NucleusBackground())
        }
    }

    func testPicker() throws {
        let current = note("cur", title: "Today")
        let host = FakeHost(notes: [
            note("a", title: "Trip to Lisbon", updated: -300), note("b", title: "Packing list", updated: -4000),
            note("c", title: "Budget 2026", updated: -90_000), note("d", title: "Book notes: Piranesi", updated: -400_000), current,
        ])
        try snapshot("plugin-backlinks-picker", height: 620) {
            NotePicker(host: host, current: current, onPick: { _ in }, onCancel: {})
        }
    }
}
