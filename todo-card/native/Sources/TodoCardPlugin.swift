import Foundation
import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Todo card: a Todo list on a note, with tasks you can check off and add from there.
public struct TodoCardPlugin: Plugin, PluginActivation {
    public let manifest: PluginManifest

    static let scopes = ["read:todo/lists", "send:todo/setDone", "send:todo/addTask"]

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: TodoCardLogic.pluginID, name: "Todo card", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "todo-list", TodoInsertAction() as any InsertAction)
        registrar.contribute(to: .noteSections, id: "todo", TodoNoteSection() as any NoteSection)
        registrar.contribute(to: .noteDetails, id: "todo", TodoNoteDetail() as any NoteDetail)
    }

    @MainActor
    public func activate(host: any NotesHost) async -> Bool {
        do {
            try await host.crossApp.ensureScopes(Self.scopes)
            return true
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to connect Todo."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Todo wasn't connected."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't connect Todo. Try again."), icon: "wifi.exclamationmark")
        }
        return false
    }
}

/// "Todo list" in the insert menu: pick a list, and it lands in the body and gets a card.
struct TodoInsertAction: InsertAction {
    var title: LocalizedStringResource { "Todo list" }
    var icon: String { "checklist" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        let data = TodoCardData(context.note.pluginData[TodoCardLogic.pluginID])
        return AnyView(
            TodoListPicker(host: context.host, attached: Set(data.lists.map(\.id)), onPick: { list in
                let current = TodoCardData(context.note.pluginData[TodoCardLogic.pluginID])
                if current.lists.contains(where: { $0.id == list.id }) {
                    context.host.show(String(localized: "“\(list.name)” is already in this note."), icon: "checklist")
                } else {
                    let updated = TodoCardLogic.attach(list, to: current, now: Date())
                    context.host.setPluginData(noteID: context.note.id, pluginID: TodoCardLogic.pluginID, value: updated.json)
                    context.insert([TodoCardLogic.embedBlock(for: list)])
                }
                context.dismiss()
            }, onCancel: { context.dismiss() })
        )
    }
}

struct TodoNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(TodoCardSection(value: context.pluginData(for: TodoCardLogic.pluginID), noteBody: context.body,
                                store: TodoCardStore(host: context.host)))
    }
}

struct TodoNoteDetail: NoteDetail {
    func chip(for note: PluginNote) -> NoteChip? { data(note).flatMap(TodoCardLogic.chip) }
    func shareLine(for note: PluginNote) -> String? { data(note).flatMap(TodoCardLogic.shareText) }
    func searchText(for note: PluginNote) -> String? { data(note).flatMap(TodoCardLogic.searchText) }

    private func data(_ note: PluginNote) -> TodoCardData? {
        note.pluginData[TodoCardLogic.pluginID].map { TodoCardData($0) }
    }
}
