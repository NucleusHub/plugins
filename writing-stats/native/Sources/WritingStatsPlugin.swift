import NotesPluginKit
import NucleusPlugins
import SwiftUI

/// Writing stats: an Info card under each note, a statistics page in Settings, and an on-device word ledger.
public struct WritingStatsPlugin: Plugin {
    public static let id = "writing-stats"
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.id, name: "Writing stats", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .noteSections, id: "writing-stats.info", InfoSection() as any NoteSection)
        registrar.contribute(to: .settingsRows, id: "writing-stats.settings", StatsSettings() as any SettingsRows)
        registrar.contribute(to: .appEvents, id: "writing-stats.events", LedgerEvents() as any AppEvents)
    }
}

struct InfoSection: NoteSection {
    @MainActor func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(InfoSectionView(context: context))
    }
}

private struct InfoSectionView: View {
    let context: NoteSectionContext
    @AppStorage("writing-stats.infoExpanded") private var expanded = false

    var body: some View {
        // The live body, so the counts follow typing.
        InfoCard(noteBody: context.body.wrappedValue, created: context.note.createdAt, edited: context.note.updatedAt, expanded: $expanded)
    }
}

struct StatsSettings: SettingsRows {
    @MainActor func view(host: any NotesHost) -> AnyView { AnyView(StatsRow(host: host)) }
}

struct LedgerEvents: AppEvents {
    @MainActor func notesChanged(host: any NotesHost) { LedgerStore.shared.notesChanged(host: host) }
    @MainActor func reset() { LedgerStore.shared.reset() }
}
