import NotesPluginKit
import NucleusPlugins
import NucleusUI
import SwiftUI

/// Daily note: one note per day, a home card with the week and the streak, and a Journal smart folder.
public struct DailyNotePlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: DailyNotes.pluginID, name: "Daily note", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .newNoteSources, id: "daily-note.today", TodaySource() as any NewNoteSource)
        registrar.contribute(to: .homeSections, id: "daily-note.home", DailyHome() as any HomeSection)
        registrar.contribute(to: .smartFolders, id: "daily-note.journal", SmartFolderDefinition(
            title: "Journal", icon: "book.closed.fill", tint: .amber,
            emptyMessage: "Your daily notes gather here. Tap Today's note on the Notes page to start one.",
            contains: { DailyNotes.dayKey(of: $0) != nil }
        ))
    }
}

struct TodaySource: NewNoteSource {
    var title: LocalizedStringResource { "Today's note" }
    var icon: String { "sun.max" }

    /// Opens today's note when there is one; otherwise hands the app the draft to create and open.
    @MainActor func makeDraft(_ context: NewNoteContext) async -> PluginNoteDraft? {
        let math = DayMath()
        let now = Date()
        if let existing = DailyNotes.note(for: math.key(for: now), in: context.host.notes) {
            context.host.open(noteID: existing.id)
            return nil
        }
        return DailyNotes.draft(for: now, folders: context.host.folders, math: math)
    }
}

struct DailyHome: HomeSection {
    @MainActor func view(host: any NotesHost) -> AnyView { AnyView(DailyHomeCard(host: host)) }
}
