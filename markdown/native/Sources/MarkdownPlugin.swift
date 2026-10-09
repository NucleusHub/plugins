import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Markdown: import `.md`/`.txt` files as notes or into a note, export or copy a note as Markdown.
public struct MarkdownPlugin: Plugin {
    public static let id = "markdown"
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.id, name: "Markdown", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "markdown.insert", ImportIntoNote() as any InsertAction)
        registrar.contribute(to: .noteActions, id: "markdown.export", ExportMarkdown() as any NoteAction)
        registrar.contribute(to: .noteActions, id: "markdown.copy", CopyMarkdown() as any NoteAction)
        registrar.contribute(to: .newNoteSources, id: "markdown.import", ImportAsNotes() as any NewNoteSource)
    }
}

struct ImportIntoNote: InsertAction {
    var title: LocalizedStringResource { "Import Markdown file" }
    var icon: String { "arrow.down.doc" }

    @MainActor func sheet(_ context: InsertContext) -> AnyView? {
        AnyView(ImportSheet(title: "Import Markdown", message: "Pick a Markdown or text file; its contents are added at the end of this note.",
                            multiple: false, onCancel: { context.dismiss() }) { files in
            let blocks = files.flatMap { MarkdownFile.blocks(text: $0.text, fileName: $0.name) }
            context.append(blocks)
            Haptics.success()
            context.dismiss()
        })
    }
}

struct ImportAsNotes: NewNoteSource {
    var title: LocalizedStringResource { "Import Markdown" }
    var icon: String { "arrow.down.doc" }

    @MainActor func sheet(_ context: NewNoteContext) -> AnyView? {
        AnyView(ImportSheet(title: "Import Markdown", message: "Pick Markdown or text files; each one becomes a note.",
                            multiple: true, onCancel: { context.finish(nil) }) { files in
            ImportAsNotes.importFiles(files, context: context)
        })
    }

    /// One file is created and opened by the app; several are created here and announced.
    @MainActor static func importFiles(_ files: [ImportedFile], context: NewNoteContext) {
        let drafts = files.map { file -> PluginNoteDraft in
            var draft = MarkdownFile.draft(text: file.text, fileName: file.name)
            draft.folderID = context.folderID
            return draft
        }
        if drafts.count == 1 {
            context.finish(drafts[0])
            return
        }
        let made = drafts.compactMap { context.host.create($0) }.count
        Haptics.success()
        context.host.show(made == 1 ? String(localized: "Imported 1 note") : String(localized: "Imported \(made) notes"), icon: "arrow.down.doc")
        context.finish(nil)
    }
}

struct ExportMarkdown: NoteAction {
    var title: LocalizedStringResource { "Export as Markdown" }
    var icon: String { "square.and.arrow.up" }

    @MainActor func sheet(_ context: NoteActionContext) -> AnyView? { AnyView(ExportSheet(context: context)) }
}

struct CopyMarkdown: NoteAction {
    var title: LocalizedStringResource { "Copy as Markdown" }
    var icon: String { "doc.on.doc" }

    @MainActor func perform(_ context: NoteActionContext) async {
        Exporter.copy(MarkdownFile.export(title: context.note.title, body: context.note.body))
        Haptics.success()
        context.host.show(String(localized: "Copied as Markdown"), icon: "doc.on.doc")
    }
}
