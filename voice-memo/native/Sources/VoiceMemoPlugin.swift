import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Voice memo: record audio into a note, with an on-device transcript that search finds.
public struct VoiceMemoPlugin: Plugin {
    public let manifest: PluginManifest
    static let pluginID = "voice-memo"

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.pluginID, name: "Voice memo", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "record", RecordAction() as any InsertAction)
        registrar.contribute(to: .noteSections, id: "player", VoiceMemoNoteSection() as any NoteSection)
        registrar.contribute(to: .noteDetails, id: "search", VoiceMemoDetail() as any NoteDetail)
    }
}

struct RecordAction: InsertAction {
    var title: LocalizedStringResource { "Voice memo" }
    var icon: String { "mic.fill" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        AnyView(RecorderSheet(onDone: { data in await insert(data, context) }, onCancel: context.dismiss))
    }

    @MainActor
    func insert(_ data: Data, _ context: InsertContext) async {
        let name = "Voice memo \(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).m4a"
        do {
            let attachment = try await context.insertAttachment(data: data, name: name, contentType: "audio/mp4", kind: .audio)
            PendingMemos.shared.attachments[attachment.id] = attachment
        } catch {
            context.host.show(String(localized: "Couldn't add the recording. Try again."), icon: "exclamationmark.triangle.fill")
        }
        context.dismiss()
    }
}

struct VoiceMemoNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(VoiceMemoSection(note: context.note, host: context.host, noteBody: context.body,
                                 value: context.pluginData(for: VoiceMemoPlugin.pluginID)))
    }
}

struct VoiceMemoDetail: NoteDetail {
    func searchText(for note: PluginNote) -> String? { Transcripts.searchText(for: note) }
}

/// "Voice memos": a player card per recording in the body.
struct VoiceMemoSection: View {
    let note: PluginNote
    let host: any NotesHost
    @Binding var noteBody: NoteBody
    @Binding var value: JSONValue?

    private var recordings: [Attachment] {
        noteBody.blocks.compactMap { block -> Attachment? in
            guard block.type == .file, let id = block.attachment else { return nil }
            let attachment = note.attachments.first { $0.id == id } ?? PendingMemos.shared.attachments[id]
            return attachment?.kind == .audio ? attachment : nil
        }
    }

    var body: some View {
        let recordings = self.recordings
        if !recordings.isEmpty {
            NucleusSection("Voice memos") {
                ForEach(recordings) { attachment in
                    PlayerCard(attachment: attachment, host: host, transcript: transcript(attachment.id),
                               save: { save($0, for: attachment.id) }, insert: { insert($0, after: attachment.id) })
                }
            }
        }
    }

    private func transcript(_ id: String) -> String? {
        note.hidden ? PendingMemos.shared.transcripts[id] : Transcripts.decode(value)[id]
    }

    private func save(_ transcript: String, for id: String) {
        // Plugin data isn't sealed in the vault, so a hidden note's transcript stays in memory.
        if note.hidden {
            PendingMemos.shared.transcripts[id] = transcript
        } else {
            value = Transcripts.setting(transcript, for: id, in: value, body: noteBody)
        }
    }

    private func insert(_ transcript: String, after id: String) {
        let blocks = transcript.components(separatedBy: "\n").map { Block(.quote, text: $0) }
        withAnimation(NucleusMotion.quick) {
            if let index = noteBody.blocks.firstIndex(where: { $0.attachment == id }) {
                noteBody.blocks.insert(contentsOf: blocks, at: index + 1)
            } else {
                noteBody.blocks.append(contentsOf: blocks)
            }
        }
        Haptics.success()
        host.show(String(localized: "Transcript added to the note"), icon: "text.quote")
    }
}
