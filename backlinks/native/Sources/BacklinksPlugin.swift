import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Backlinks: links between notes, and a "Linked from" section on the note they point at.
public struct BacklinksPlugin: Plugin {
    public let manifest: PluginManifest
    static let pluginID = "backlinks"

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.pluginID, name: "Backlinks", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "link", LinkToNoteAction() as any InsertAction)
        registrar.contribute(to: .noteActions, id: "convert", ConvertLinksAction() as any NoteAction)
        registrar.contribute(to: .noteSections, id: "linked-from", LinkedFromNoteSection() as any NoteSection)
        registrar.contribute(to: .noteDetails, id: "backlinks", BacklinksDetail() as any NoteDetail)
        registrar.contribute(to: .appEvents, id: "index", BacklinksEvents() as any AppEvents)
    }
}

struct LinkToNoteAction: InsertAction {
    var title: LocalizedStringResource { "Link to note" }
    var icon: String { "link" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        AnyView(NotePicker(host: context.host, current: context.note) { picked in
            let title = picked.displayTitle ?? String(localized: "New note")
            // The kit inserts whole blocks, so the link gets a paragraph of its own.
            context.insert([Block(.paragraph, runs: [Run(title, link: NoteLink.url(for: picked.id))])])
            context.dismiss()
        } onCancel: {
            context.dismiss()
        })
    }
}

struct ConvertLinksAction: NoteAction {
    var title: LocalizedStringResource { "Convert [[links]]" }
    var icon: String { "link.badge.plus" }

    func isAvailable(for note: PluginNote) -> Bool {
        note.body.blocks.contains { $0.runs.contains { $0.text.contains("[[") } }
    }

    @MainActor
    func perform(_ context: NoteActionContext) async {
        let host = context.host
        // The latest saved copy, in case the snapshot is older.
        let note = host.notes.first { $0.id == context.note.id } ?? context.note
        let titles = WikiLinks.titles(in: note.body)
        guard !titles.isEmpty else {
            host.show(String(localized: "No [[links]] to convert"), icon: "link")
            return
        }
        let candidates = host.notes.filter { note.hidden || !$0.hidden }
        var ids = WikiLinks.resolve(titles, in: candidates)
        let missing = titles.filter { ids[NoteSearch.fold($0)] == nil }
        if !missing.isEmpty {
            let list = missing.map { "“\($0)”" }.formatted(.list(type: .and))
            let create = missing.count == 1 ? String(localized: "Create note") : String(localized: "Create \(missing.count) notes")
            let message = String(localized: "No note is called \(list).")
            guard let choice = await host.confirm(title: String(localized: "Create the missing notes?"), message: message,
                                                  actions: [create, String(localized: "Link existing only")]) else { return }
            if choice == 0 {
                for title in missing {
                    let draft = PluginNoteDraft(title: title, folderID: note.folderID)
                    if let id = host.create(draft) { ids[NoteSearch.fold(title)] = id }
                }
            }
        }
        let (body, converted) = WikiLinks.apply(note.body, ids: ids)
        guard converted > 0 else {
            host.show(String(localized: "Nothing was linked"), icon: "link")
            return
        }
        host.updateNote(id: note.id, title: nil, body: body)
        host.show(converted == 1 ? String(localized: "Linked 1 note") : String(localized: "Linked \(converted) notes"), icon: "link")
    }
}

struct LinkedFromNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(LinkedFromSection(note: context.note, host: context.host))
    }
}

struct BacklinksDetail: NoteDetail {
    func chip(for note: PluginNote) -> NoteChip? {
        let count = BacklinkSnapshot.shared.index?.backlinks(to: note).count ?? 0
        return count > 0 ? NoteChip(icon: "arrow.uturn.left", text: "\(count)") : nil
    }
}

struct BacklinksEvents: AppEvents {
    @MainActor func notesChanged(host: any NotesHost) { BacklinkIndexer.shared.notesChanged(host.notes) }
    @MainActor func reset() { BacklinkIndexer.shared.reset() }
}
