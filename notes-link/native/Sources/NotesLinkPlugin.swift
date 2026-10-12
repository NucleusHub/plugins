import NucleusPlugins
import NucleusUI
import SwiftUI
import TodoPluginKit

/// Notes link: a note from Notes on a task.
public struct NotesLinkPlugin: Plugin, PluginActivation {
    public let manifest: PluginManifest

    static let scopes = ["read:notes/notes", "send:notes/createNote"]

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: NotesRefresh.pluginID, name: "Notes link", version: "1.0.0", target: ["todo"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .editorSections, id: "note", NoteEditorSection() as any TaskEditorSection)
        registrar.contribute(to: .taskDetails, id: "note", NoteDetail() as any TaskDetail)
        registrar.contribute(to: .appEvents, id: "note", NoteEvents() as any AppEvents)
    }

    @MainActor
    public func activate(host: any TodoHost) async -> Bool {
        do {
            try await host.crossApp.ensureScopes(Self.scopes)
            return true
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to link Notes."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Notes wasn't connected."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't connect Notes. Try again."), icon: "wifi.exclamationmark")
        }
        return false
    }
}

struct NoteEditorSection: TaskEditorSection {
    @MainActor
    func view(_ context: TaskEditorContext) -> AnyView {
        AnyView(NoteSection(value: context.pluginData(for: NotesRefresh.pluginID), title: context.title, notes: context.notes,
                            taskID: context.taskID, host: context.host))
    }

    var toolbarItem: TaskEditorToolbarItem? { TaskEditorToolbarItem(title: "Note", icon: "note.text") }
    @MainActor func isAttached(_ context: TaskEditorContext) -> Bool { context.pluginData(for: NotesRefresh.pluginID).wrappedValue != nil }
}

struct NoteDetail: TaskDetail {
    func chip(for task: PluginTask) -> TaskChip? { link(task).map { TaskChip(icon: "note.text", text: $0.title, url: $0.pending == nil ? $0.url : nil) } }
    func shareLine(for task: PluginTask) -> String? { link(task).map { "📝 \($0.title)" } }
    func searchText(for task: PluginTask) -> String? { link(task)?.title }

    private func link(_ task: PluginTask) -> NoteLink? { NoteLink(task.pluginData[NotesRefresh.pluginID]) }
}

struct NoteEvents: AppEvents {
    @MainActor func tasksChanged(host: any TodoHost) { NotesRefresh.shared.refresh(host) }
    @MainActor func reset() { NotesRefresh.shared.forget() }
}
