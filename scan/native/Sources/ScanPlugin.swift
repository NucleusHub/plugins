import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Scan: paper documents into a note as images, with their text recognized on the device for search.
public struct ScanPlugin: Plugin {
    public let manifest: PluginManifest
    static let pluginID = "scan"

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.pluginID, name: "Scan", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "scan", ScanInsertAction() as any InsertAction)
        registrar.contribute(to: .newNoteSources, id: "scan", ScanNewNote() as any NewNoteSource)
        registrar.contribute(to: .noteSections, id: "text", ScannedTextNoteSection() as any NoteSection)
        registrar.contribute(to: .noteDetails, id: "search", ScanDetail() as any NoteDetail)
    }

    @MainActor static func showUnsupported(_ host: any NotesHost) {
        host.show(String(localized: "Scanning needs a camera. Try it on your iPhone."), icon: "camera.fill")
    }
}

struct ScanInsertAction: InsertAction {
    var title: LocalizedStringResource { "Scan document" }
    var icon: String { "doc.viewfinder" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        guard Scanner.isSupported else { return nil }
        return AnyView(ScanSheet(onPages: { pages in await insert(pages, context) }, onCancel: context.dismiss))
    }

    // Only reached without a sheet: no camera here.
    @MainActor
    func perform(_ context: InsertContext) async { ScanPlugin.showUnsupported(context.host) }

    @MainActor
    func insert(_ pages: [ScannedPage], _ context: InsertContext) async {
        let host = context.host
        var texts: [String: String] = [:]
        do {
            for (index, page) in pages.enumerated() {
                let attachment = try await context.insertAttachment(data: page.jpeg, name: "Scan \(index + 1).jpg",
                                                                    contentType: "image/jpeg", kind: .image)
                PendingScans.shared.attachments[attachment.id] = attachment
                // Plugin data isn't sealed in the vault, so a hidden note gets its text in the (sealed) body instead.
                if context.note.hidden {
                    if !page.text.isEmpty { context.insert(ScanTexts.blocks(for: page.text)) }
                } else {
                    texts[attachment.id] = page.text
                }
            }
        } catch {
            host.show(String(localized: "Couldn't add the scan. Try again."), icon: "exclamationmark.triangle.fill")
        }
        if !texts.isEmpty {
            PendingScans.shared.texts.merge(texts) { $1 }
            let saved = host.notes.first { $0.id == context.note.id } ?? context.note
            let merged = ScanTexts.decode(saved.pluginData[ScanPlugin.pluginID]).merging(texts) { $1 }
            host.setPluginData(noteID: context.note.id, pluginID: ScanPlugin.pluginID, value: ScanTexts.encode(merged))
        }
        context.dismiss()
    }
}

struct ScanNewNote: NewNoteSource {
    var title: LocalizedStringResource { "Scan a document" }
    var icon: String { "doc.viewfinder" }

    @MainActor
    func sheet(_ context: NewNoteContext) -> AnyView? {
        guard Scanner.isSupported else { return nil }
        return AnyView(ScanSheet(onPages: { pages in await finish(pages, context) }, onCancel: { context.finish(nil) }))
    }

    @MainActor
    func makeDraft(_ context: NewNoteContext) async -> PluginNoteDraft? {
        ScanPlugin.showUnsupported(context.host)
        return nil
    }

    @MainActor
    func finish(_ pages: [ScannedPage], _ context: NewNoteContext) async {
        var blocks: [Block] = []
        var texts: [String: String] = [:]
        for (index, page) in pages.enumerated() {
            guard let attachment = try? await context.host.addAttachment(data: page.jpeg, name: "Scan \(index + 1).jpg",
                                                                         contentType: "image/jpeg", kind: .image) else { continue }
            PendingScans.shared.attachments[attachment.id] = attachment
            blocks.append(Block(.image, attachment: attachment.id))
            texts[attachment.id] = page.text
        }
        guard !blocks.isEmpty else {
            context.host.show(String(localized: "Couldn't add the scan. Try again."), icon: "exclamationmark.triangle.fill")
            return context.finish(nil)
        }
        var pluginData: [String: JSONValue] = [:]
        pluginData[ScanPlugin.pluginID] = ScanTexts.encode(texts.filter { !$0.value.isEmpty })
        context.finish(PluginNoteDraft(title: ScanTexts.title(for: .now), body: NoteBody(blocks: blocks + [Block(text: "")]),
                                       folderID: context.folderID, pluginData: pluginData))
    }
}

struct ScannedTextNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(ScannedTextSection(note: context.note, host: context.host, noteBody: context.body,
                                   value: context.pluginData(for: ScanPlugin.pluginID)))
    }
}

struct ScanDetail: NoteDetail {
    func searchText(for note: PluginNote) -> String? { ScanTexts.searchText(for: note) }
}
