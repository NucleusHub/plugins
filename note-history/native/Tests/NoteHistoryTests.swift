@testable import NoteHistoryPlugin
import NotesPluginKit
import NucleusUI
import SwiftUI
import XCTest

private func tempStore() -> HistoryStore {
    HistoryStore(root: FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)", directoryHint: .isDirectory))
}

// Fixed block ids, as a real body keeps them across edits.
private func edited(_ id: String, _ text: String, at seconds: TimeInterval, hidden: Bool = false) -> PluginNote {
    let body = NoteBody(blocks: text.components(separatedBy: "\n").enumerated().map { Block(id: "b\($0.offset)", .paragraph, runs: [Run($0.element)]) })
    return PluginNote(id: id, displayTitle: "T", title: "T", body: body, folderID: nil, tags: [], color: nil,
               pinned: false, hidden: hidden, updatedAt: Date(timeIntervalSince1970: seconds), createdAt: .distantPast, attachments: [])
}

final class HistoryStoreTests: XCTestCase {
    func testSavesNewestFirstAndKeepsFifty() {
        let store = tempStore()
        defer { store.clearAll() }
        for i in 0..<55 {
            store.save(NoteVersion(savedAt: Date(timeIntervalSince1970: TimeInterval(1000 + i)), title: "v\(i)", body: NoteBody()), noteID: "n1")
        }
        let versions = store.versions(of: "n1")
        XCTAssertEqual(versions.count, HistoryStore.maxVersions)
        XCTAssertEqual(versions.first?.title, "v54")
        XCTAssertEqual(versions.last?.title, "v5")
        XCTAssertEqual(store.latest(of: "n1")?.title, "v54")
    }

    func testPruneDeleteAndUsage() {
        let store = tempStore()
        defer { store.clearAll() }
        for id in ["a", "b", "c"] { store.save(NoteVersion(savedAt: .now, title: id, body: NoteBody(plainText: "hello")), noteID: id) }
        XCTAssertEqual(store.usage().notes, 3)
        XCTAssertGreaterThan(store.usage().bytes, 0)
        store.prune(keeping: ["a", "b"])
        XCTAssertEqual(Set(store.noteIDs()), ["a", "b"])
        store.delete("a")
        XCTAssertFalse(store.hasHistory("a"))
        store.clearAll()
        XCTAssertEqual(store.usage().notes, 0)
    }

    func testRefusesIDsThatEscapeTheFolder() {
        let store = tempStore()
        store.save(NoteVersion(savedAt: .now, title: "x", body: NoteBody()), noteID: "../evil")
        XCTAssertTrue(store.noteIDs().isEmpty)
    }
}

@MainActor
final class HistoryRecorderTests: XCTestCase {
    func testCapturesPreviousStateThrottledToTwoMinutes() {
        let store = tempStore()
        defer { store.clearAll() }
        var clock = Date(timeIntervalSince1970: 10_000)
        let recorder = HistoryRecorder(store: store, now: { clock })

        recorder.notesChanged([edited("n", "one", at: 1)])          // seeds, saves nothing
        XCTAssertTrue(store.versions(of: "n").isEmpty)
        recorder.notesChanged([edited("n", "one two", at: 2)])      // saves "one"
        clock += 60
        recorder.notesChanged([edited("n", "one two three", at: 3)]) // within 2 min: skipped
        clock += 61
        recorder.notesChanged([edited("n", "four", at: 4)])          // saves "one two three"
        XCTAssertEqual(store.versions(of: "n").map(\.body.plainText), ["one two three", "one"])
    }

    func testSkipsUnchangedTextAndDuplicates() {
        let store = tempStore()
        defer { store.clearAll() }
        var clock = Date(timeIntervalSince1970: 10_000)
        let recorder = HistoryRecorder(store: store, now: { clock })
        recorder.notesChanged([edited("n", "same", at: 1)])
        recorder.notesChanged([edited("n", "same", at: 2)])          // pinned or colored: text unchanged
        XCTAssertTrue(store.versions(of: "n").isEmpty)
        recorder.notesChanged([edited("n", "changed", at: 3)])
        clock += 500
        recorder.notesChanged([edited("n", "same", at: 4)])
        clock += 500
        recorder.notesChanged([edited("n", "same again", at: 5)])
        XCTAssertEqual(store.versions(of: "n").map(\.body.plainText), ["same", "changed", "same"])
    }

    func testHiddenNotesNeverWrittenAndLoseHistory() {
        let store = tempStore()
        defer { store.clearAll() }
        var clock = Date(timeIntervalSince1970: 10_000)
        let recorder = HistoryRecorder(store: store, now: { clock })
        recorder.notesChanged([edited("n", "a", at: 1), edited("h", "secret", at: 1, hidden: true)])
        recorder.notesChanged([edited("n", "b", at: 2), edited("h", "secret 2", at: 2, hidden: true)])
        XCTAssertFalse(store.hasHistory("h"))
        XCTAssertTrue(store.hasHistory("n"))
        clock += 1000
        recorder.notesChanged([edited("n", "c", at: 3, hidden: true)])
        XCTAssertFalse(store.hasHistory("n"))
        recorder.saveNow(edited("n", "c", at: 3, hidden: true))
        XCTAssertFalse(store.hasHistory("n"))
    }

    func testPrunesMissingNotesButNotOnAnEmptyList() {
        let store = tempStore()
        defer { store.clearAll() }
        var clock = Date(timeIntervalSince1970: 10_000)
        let recorder = HistoryRecorder(store: store, now: { clock })
        store.save(NoteVersion(savedAt: clock, title: "x", body: NoteBody(plainText: "x")), noteID: "gone")
        recorder.notesChanged([])
        XCTAssertTrue(store.hasHistory("gone"))
        recorder.notesChanged([edited("n", "a", at: 1)])
        XCTAssertFalse(store.hasHistory("gone"))
        store.save(NoteVersion(savedAt: clock, title: "x", body: NoteBody(plainText: "x")), noteID: "gone2")
        clock += 60
        recorder.notesChanged([edited("n", "a", at: 1)])
        XCTAssertTrue(store.hasHistory("gone2"), "prunes at most every 10 minutes")
        clock += 600
        recorder.notesChanged([edited("n", "a", at: 1)])
        XCTAssertFalse(store.hasHistory("gone2"))
    }

    func testSaveNowIgnoresTheInterval() {
        let store = tempStore()
        defer { store.clearAll() }
        let clock = Date(timeIntervalSince1970: 10_000)
        let recorder = HistoryRecorder(store: store, now: { clock })
        recorder.notesChanged([edited("n", "a", at: 1)])
        recorder.notesChanged([edited("n", "b", at: 2)])
        recorder.saveNow(edited("n", "b", at: 2))
        XCTAssertEqual(store.versions(of: "n").count, 1, "same millisecond overwrites")
        XCTAssertEqual(store.latest(of: "n")?.body.plainText, "b")
    }
}

final class TextDiffTests: XCTestCase {
    func testLineDiff() {
        let diff = TextDiff.lines(from: ["a", "b", "c", "d"], to: ["a", "x", "c", "d", "e"])
        XCTAssertEqual(diff, [
            .init(kind: .same, text: "a"), .init(kind: .removed, text: "b"), .init(kind: .added, text: "x"),
            .init(kind: .same, text: "c"), .init(kind: .same, text: "d"), .init(kind: .added, text: "e"),
        ])
        XCTAssertEqual(TextDiff.lines(from: [], to: ["a"]), [.init(kind: .added, text: "a")])
        XCTAssertEqual(TextDiff.lines(from: ["a"], to: []), [.init(kind: .removed, text: "a")])
        XCTAssertTrue(TextDiff.lines(from: ["a", "b"], to: ["a", "b"]).allSatisfy { $0.kind == .same })
    }

    func testBodyAsLines() {
        let body = NoteBody(blocks: [
            Block(.heading1, text: "Plan"), Block(.numbered, text: "One"), Block(.numbered, text: "Two"),
            Block(.check, text: "Done", checked: true), Block(.bullet, text: "Deep", indent: 1), Block(.quote, text: "Q"),
            Block(.image, attachment: "img"),
        ])
        XCTAssertEqual(TextDiff.text(title: "T", body: body), ["T", "# Plan", "1. One", "2. Two", "☑ Done", "  • Deep", "> Q", "[Image]"])
    }

    func testNumberingRestartsAfterOtherBlocks() {
        let blocks = [
            Block(.numbered, text: "a"), Block(.numbered, text: "a.1", indent: 1), Block(.numbered, text: "b"),
            Block(.paragraph, text: "break"), Block(.numbered, text: "c"),
        ]
        XCTAssertEqual(BodyNumbering.numbers(for: blocks), [0: 1, 1: 1, 2: 2, 4: 1])
    }

    func testWordCountIncludesTitle() {
        XCTAssertEqual(NoteVersion(savedAt: .now, title: "Two words", body: NoteBody(plainText: "and three more")).wordCount, 5)
    }
}

@MainActor
final class NoteHistorySnapshots: XCTestCase {
    private var sample: (PluginNote, HistoryStore) {
        let store = tempStore()
        let current = PluginNote(id: "n", displayTitle: "Weekend in Prague", title: "Weekend in Prague", body: NoteBody(blocks: [
            Block(.heading2, text: "Saturday"),
            Block(.check, text: "Book the table at Lokál", checked: true),
            Block(.check, text: "Castle in the morning"),
            Block(.bullet, text: "Tram 22 from Národní"),
            Block(.paragraph, text: "Sunday: farmers market at Náplavka, then a walk to Vyšehrad."),
        ]), folderID: nil, tags: [], color: nil, pinned: false, hidden: false, updatedAt: .now, createdAt: .now, attachments: [])
        let older: [(TimeInterval, NoteBody)] = [
            (-86_400 * 3, NoteBody(plainText: "Ideas for the weekend")),
            (-86_400, NoteBody(blocks: [Block(.heading2, text: "Saturday"), Block(.check, text: "Book a table"),
                                        Block(.check, text: "Castle in the morning")])),
            (-3_000, NoteBody(blocks: [
                Block(.heading2, text: "Saturday"), Block(.check, text: "Book the table at Lokál", checked: true),
                Block(.check, text: "Castle in the morning"), Block(.numbered, text: "Old town square"), Block(.numbered, text: "Charles Bridge"),
                Block(.quote, text: "Bring a jacket, evenings get cold."),
            ])),
        ]
        for (offset, body) in older {
            store.save(NoteVersion(savedAt: Date().addingTimeInterval(offset), title: "Weekend in Prague", body: body), noteID: "n")
        }
        return (current, store)
    }

    func testHistorySheet() throws {
        let (current, store) = sample
        defer { store.clearAll() }
        let host = FakeHost(notes: [current])
        try snapshot("plugin-note-history-sheet", height: 760) {
            HistorySheet(noteID: "n", fallback: current, host: host, store: store, recorder: HistoryRecorder(store: store), dismiss: {})
        }
    }

    func testVersionPreviewAndDiff() throws {
        let (current, store) = sample
        defer { store.clearAll() }
        let version = store.latest(of: "n")!
        try snapshot("plugin-note-history-version", height: 760) {
            VersionDetail(version: version, current: current, back: {}, restore: {})
        }
        try snapshot("plugin-note-history-diff") {
            DiffView(lines: TextDiff.lines(from: TextDiff.text(title: version.title, body: version.body),
                                           to: TextDiff.text(title: current.title, body: current.body)))
                .padding(18)
                .nucleusGlass(cornerRadius: NucleusRadius.card)
                .padding(16)
                .background(NucleusBackground())
        }
    }

    func testSettingsRow() throws {
        let (_, store) = sample
        defer { store.clearAll() }
        try snapshot("plugin-note-history-settings") {
            NucleusSection("Notes") { HistorySettingsRow(host: FakeHost(), store: store) }
                .padding(16)
                .background(NucleusBackground())
        }
    }
}
