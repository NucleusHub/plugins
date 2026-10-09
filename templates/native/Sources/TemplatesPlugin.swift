import NotesPluginKit
import NucleusPlugins
import SwiftUI

/// Templates: new notes from built-in or saved templates, and "Save as template" in a note's More menu.
public struct TemplatesPlugin: Plugin {
    public static let id = "templates"
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.id, name: "Templates", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .newNoteSources, id: "templates.new", TemplateSource() as any NewNoteSource)
        registrar.contribute(to: .noteActions, id: "templates.save", SaveAsTemplate() as any NoteAction)
        registrar.contribute(to: .appEvents, id: "templates.events", TemplateEvents() as any AppEvents)
    }
}

struct TemplateSource: NewNoteSource {
    var title: LocalizedStringResource { "From a template" }
    var icon: String { "square.on.square" }

    @MainActor func sheet(_ context: NewNoteContext) -> AnyView? { AnyView(TemplatesSheet(context: context)) }
}

struct SaveAsTemplate: NoteAction {
    var title: LocalizedStringResource { "Save as template" }
    var icon: String { "square.on.square" }

    func isAvailable(for note: PluginNote) -> Bool { !note.title.isEmpty || !note.body.isEmpty }

    @MainActor func sheet(_ context: NoteActionContext) -> AnyView? { AnyView(SaveTemplateSheet(context: context)) }
}

struct TemplateEvents: AppEvents {
    @MainActor func reset() { TemplateStore.shared.removeAll() }
}
