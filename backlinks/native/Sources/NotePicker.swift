import NotesPluginKit
import NucleusUI
import SwiftUI

/// A searchable list of notes to link to, most recently edited first.
struct NotePicker: View {
    let host: any NotesHost
    let current: PluginNote
    let onPick: (PluginNote) -> Void
    let onCancel: () -> Void
    @State private var query = ""
    @FocusState private var searching: Bool
    // A long list is slow to lay out and nobody scrolls it; typing narrows it down.
    static let limit = 60

    var body: some View {
        let (shown, total) = Self.filter(host.notes, query: query, current: current)
        NucleusSheetPage("Link to note", onCancel: onCancel) {
            searchField
                .padding(.bottom, 18)
            if shown.isEmpty {
                NucleusEmptyState("doc.text.magnifyingglass", title: query.isEmpty ? "No other notes" : "No matches",
                                  message: query.isEmpty ? "Write another note, then link to it here." : "Try another title.")
                    .padding(.top, 40)
            } else {
                NucleusSection(footer: total > shown.count ? Text("Type to find the other \(total - shown.count) notes.") : nil) {
                    ForEach(shown) { note in
                        Button { onPick(note) } label: { row(note) }
                            .buttonStyle(NucleusRowButtonStyle())
                    }
                }
            }
        }
        .onAppear { searching = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Nucleus.secondaryText)
            TextField("Search notes", text: $query)
                .font(.system(size: 16))
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .nucleusGlass(in: Capsule())
    }

    private func row(_ note: PluginNote) -> some View {
        NucleusRow(verbatim: note.displayTitle ?? String(localized: "New note"),
                   subtitle: Text(note.updatedAt, format: .relative(presentation: .named)),
                   icon: IconTile(note.hidden ? "eye.slash.fill" : "doc.text.fill", tint: tint(note))) {
            Image(systemName: "link")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Nucleus.accent)
        }
    }

    private func tint(_ note: PluginNote) -> NucleusTint {
        if case .tint(let name) = note.color, let tint = NucleusTint(rawValue: name) { return tint }
        return .slate
    }

    /// Notes matching the query (folded, every word), without the current one; hidden ones only from a hidden note.
    static func filter(_ notes: [PluginNote], query: String, current: PluginNote, limit: Int = limit) -> (shown: [PluginNote], total: Int) {
        let words = NoteSearch.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let matching = notes
            .filter { $0.id != current.id && (current.hidden || !$0.hidden) }
            .filter { note in
                guard !words.isEmpty else { return true }
                let title = NoteSearch.fold(note.displayTitle ?? "")
                return words.allSatisfy { title.contains($0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        return (Array(matching.prefix(limit)), matching.count)
    }
}
