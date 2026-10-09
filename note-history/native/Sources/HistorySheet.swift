import NotesPluginKit
import NucleusUI
import SwiftUI

/// The list of a note's versions, newest first; tapping one opens it.
struct HistorySheet: View {
    let noteID: String
    let fallback: PluginNote
    let host: any NotesHost
    let store: HistoryStore
    let recorder: HistoryRecorder
    let dismiss: () -> Void
    @State private var versions: [NoteVersion]?
    @State private var selected: NoteVersion?

    private var current: PluginNote { host.notes.first { $0.id == noteID } ?? fallback }

    var body: some View {
        ZStack {
            if let selected {
                VersionDetail(version: selected, current: current, back: { withAnimation(NucleusMotion.quick) { self.selected = nil } },
                              restore: { await restore(selected) })
                    .transition(.move(edge: .trailing))
            } else {
                list.transition(.move(edge: .leading))
            }
        }
        .task { if versions == nil { versions = store.versions(of: noteID) } }
    }

    private var list: some View {
        NucleusSheetPage("Version history", onCancel: dismiss) {
            if let versions, versions.isEmpty {
                NucleusEmptyState("clock.arrow.circlepath", title: "No versions yet",
                                  message: "As you edit this note, earlier versions are saved here on this device.")
                    .padding(.top, 60)
            } else if let versions {
                NucleusSection("Now") {
                    NucleusRow("Current version", subtitle: Text(words(current.title, current.body)),
                               icon: IconTile("pencil.line", tint: .indigo))
                }
                NucleusSection("Earlier", footer: Text("Kept on this device only: up to 50 versions per note, saved when you return to a note after a pause.")) {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        Button {
                            withAnimation(NucleusMotion.quick) { selected = version }
                        } label: {
                            row(version, delta: index + 1 < versions.count ? version.wordCount - versions[index + 1].wordCount : nil)
                        }
                        .buttonStyle(NucleusRowButtonStyle())
                    }
                }
            }
        }
    }

    private func row(_ version: NoteVersion, delta: Int?) -> some View {
        HStack(spacing: 12) {
            IconTile("clock", tint: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(version.savedAt, format: .relative(presentation: .named))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                Text(verbatim: "\(version.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(words(version.title, version.body))")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DeltaPill(delta: delta)
            Chevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func words(_ title: String, _ body: NoteBody) -> String {
        let count = NoteVersion(savedAt: .now, title: title, body: body).wordCount
        return count == 1 ? String(localized: "1 word") : String(localized: "\(count) words")
    }

    private func restore(_ version: NoteVersion) async {
        let picked = await host.confirm(title: String(localized: "Restore this version?"),
                                        message: String(localized: "The note as it is now is saved as a version first, so you can switch back."),
                                        actions: [String(localized: "Restore")])
        guard picked == 0 else { return }
        recorder.saveNow(current)
        host.updateNote(id: noteID, title: version.title, body: version.body)
        host.show(String(localized: "Version restored"), icon: "clock.arrow.circlepath")
        dismiss()
    }
}

/// "+12" in green, "−3" in red: how many words the version added or removed against the one before.
struct DeltaPill: View {
    let delta: Int?

    var body: some View {
        let (text, color): (String, Color) = switch delta {
        case nil: (String(localized: "First"), Nucleus.secondaryText)
        case 0: ("±0", Nucleus.secondaryText)
        case let d? where d > 0: ("+\(d)", Nucleus.success)
        case let d?: ("−\(-d)", Nucleus.danger)
        }
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(color.opacity(0.12)))
            .accessibilityLabel(delta.map { "\($0) words" } ?? "First version")
    }
}
