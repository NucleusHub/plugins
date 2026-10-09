@testable import VoiceMemoPlugin
import NotesPluginKit
import NucleusUI
import SwiftUI
import XCTest

final class TranscriptTests: XCTestCase {
    func testStorageAndSearchText() {
        let body = NoteBody(blocks: [Block(.file, attachment: "a2"), Block(text: "x"), Block(.file, attachment: "a1")])
        var value = Transcripts.setting("first memo", for: "a1", in: nil, body: body)
        value = Transcripts.setting("second memo", for: "a2", in: value, body: body)
        XCTAssertEqual(Transcripts.decode(value), ["a1": "first memo", "a2": "second memo"])
        let n = note("n", title: "Ideas", body: body, pluginData: ["voice-memo": value!])
        XCTAssertEqual(Transcripts.searchText(for: n), "second memo\nfirst memo")
        XCTAssertEqual(VoiceMemoDetail().searchText(for: n), "second memo\nfirst memo")
    }

    func testSettingDropsRecordingsNoLongerInTheBody() {
        let body = NoteBody(blocks: [Block(.file, attachment: "a1")])
        let old: JSONValue = .object(["gone": "old", "a1": "keep"])
        XCTAssertEqual(Transcripts.decode(Transcripts.setting("new", for: "a1", in: old, body: body)), ["a1": "new"])
    }

    func testLocalePick() {
        let supported: Set = ["en-US", "en_GB", "cs-CZ", "de-DE"]
        XCTAssertEqual(Transcripts.locale(current: Locale(identifier: "cs_CZ"), supported: supported).identifier, "cs-CZ")
        XCTAssertEqual(Transcripts.locale(current: Locale(identifier: "en_GB"), supported: supported).identifier, "en-GB")
        XCTAssertEqual(Transcripts.locale(current: Locale(identifier: "de_AT"), supported: supported).identifier, "de-DE")
        XCTAssertEqual(Transcripts.locale(current: Locale(identifier: "ja_JP"), supported: supported).identifier, "en-US")
    }

    func testAudioMath() {
        XCTAssertEqual(AudioMath.clock(0), "0:00")
        XCTAssertEqual(AudioMath.clock(75.9), "1:15")
        XCTAssertEqual(AudioMath.clock(3725), "1:02:05")
        XCTAssertEqual(AudioMath.level(decibels: -160), 0)
        XCTAssertEqual(AudioMath.level(decibels: 0), 1)
        XCTAssertEqual(AudioMath.level(decibels: -25), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioMath.level(decibels: -.infinity), 0)
        XCTAssertEqual(AudioMath.normalizedBars([0, 0.5, 1]), [0.06, 0.5, 1])
        XCTAssertEqual(AudioMath.normalizedBars([0, 0]), [0.06, 0.06])
        XCTAssertEqual([AudioMath.nextRate(after: 1), AudioMath.nextRate(after: 1.5), AudioMath.nextRate(after: 2)], [1.5, 2, 1])
        XCTAssertEqual(AudioMath.rateLabel(1.5), "1.5×")
        XCTAssertEqual(AudioMath.rateLabel(2), "2×")
    }

    @MainActor
    func testInsertAddsAudioFileBlock() async {
        let current = note("n", title: "Ideas")
        let host = FakeHost(notes: [current])
        var inserted: [Block] = []
        await RecordAction().insert(Data([1, 2]), InsertContext(note: current, host: host, insert: { inserted += $0 }, append: { _ in }))
        XCTAssertEqual(inserted.map(\.type), [.file])
        let id = inserted[0].attachment!
        XCTAssertEqual(PendingMemos.shared.attachments[id]?.kind, .audio)
        XCTAssertEqual(PendingMemos.shared.attachments[id]?.contentType, "audio/mp4")
    }
}

@MainActor
final class VoiceMemoSnapshots: XCTestCase {
    func testPlayerCardAndRecorder() throws {
        let attachment = Attachment(id: "a1", name: "Voice memo.m4a", contentType: "audio/mp4", size: 1, sha256: "", kind: .audio)
        let body = NoteBody(blocks: [Block(.file, attachment: "a1")])
        let n = note("n", title: "Ideas", body: body, attachments: [attachment])
        let value = Transcripts.encode(["a1": "Remind Petra about the tram passes, and book the table at Lokál for Saturday at seven. Bring the camera."])
        try snapshot("plugin-voice-memo-player") {
            VoiceMemoSection(note: n, host: FakeHost(), noteBody: .constant(body), value: .constant(value))
                .padding(16)
                .background(NucleusBackground())
        }
        try snapshot("plugin-voice-memo-recorder", height: 640) {
            RecorderSheet(onDone: { _ in }, onCancel: {})
        }
    }
}
