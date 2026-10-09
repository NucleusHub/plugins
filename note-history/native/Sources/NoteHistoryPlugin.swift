import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Note history: earlier versions of each note, kept on this device, to compare and restore.
public struct NoteHistoryPlugin: Plugin {
    public let manifest: PluginManifest
    static let pluginID = "note-history"

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.pluginID, name: "Note history", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .noteActions, id: "history", VersionHistoryAction() as any NoteAction)
        registrar.contribute(to: .settingsRows, id: "storage", HistorySettings() as any SettingsRows)
        registrar.contribute(to: .appEvents, id: "recorder", HistoryEvents() as any AppEvents)
    }
}

struct VersionHistoryAction: NoteAction {
    var title: LocalizedStringResource { "Version history" }
    var icon: String { "clock.arrow.circlepath" }

    // Vault notes keep no history.
    func isAvailable(for note: PluginNote) -> Bool { !note.hidden }

    @MainActor
    func sheet(_ context: NoteActionContext) -> AnyView? {
        AnyView(HistorySheet(noteID: context.note.id, fallback: context.note, host: context.host, store: .shared,
                             recorder: .shared, dismiss: context.dismiss))
    }
}

struct HistorySettings: SettingsRows {
    @MainActor
    func view(host: any NotesHost) -> AnyView {
        AnyView(HistorySettingsRow(host: host, store: .shared))
    }
}

struct HistoryEvents: AppEvents {
    @MainActor func notesChanged(host: any NotesHost) { HistoryRecorder.shared.notesChanged(host.notes) }

    @MainActor func reset() {
        HistoryRecorder.shared.forget()
        HistoryStore.shared.clearAll()
    }
}

/// "Note history · 1.2 MB on this device" with a Clear button.
struct HistorySettingsRow: View {
    let host: any NotesHost
    let store: HistoryStore
    @State private var usage: (bytes: Int, notes: Int)?

    var body: some View {
        NucleusRow("Note history", subtitle: Text(subtitle), icon: IconTile("clock.arrow.circlepath", tint: .teal)) {
            Button("Clear", role: .destructive) {
                Task { await clear() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Nucleus.danger)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Nucleus.danger.opacity(0.12)))
            .buttonStyle(NucleusPressStyle())
            .disabled((usage?.notes ?? 0) == 0)
            .opacity((usage?.notes ?? 0) == 0 ? 0.4 : 1)
        }
        .task { usage = store.usage() }
    }

    private var subtitle: String {
        guard let usage else { return " " }
        guard usage.notes > 0 else { return String(localized: "No versions saved yet") }
        let size = usage.bytes.formatted(.byteCount(style: .file))
        return usage.notes == 1 ? String(localized: "\(size) for 1 note, on this device")
            : String(localized: "\(size) for \(usage.notes) notes, on this device")
    }

    private func clear() async {
        let picked = await host.confirm(title: String(localized: "Clear all history?"),
                                        message: String(localized: "Every saved version of every note is deleted from this device. Your notes stay as they are."),
                                        actions: [String(localized: "Clear history")])
        guard picked == 0 else { return }
        store.clearAll()
        HistoryRecorder.shared.forget()
        usage = store.usage()
        host.show(String(localized: "History cleared"), icon: "trash")
    }
}
