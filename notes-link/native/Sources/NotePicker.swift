import NucleusUI
import SwiftUI
import TodoPluginKit

/// Notes' shared notes, searchable; pinned first, then the most recently edited.
struct NotePicker: View {
    let host: any TodoHost
    let current: NoteLink?
    let onPick: (SharedNote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [SharedNote]?
    @State private var failure: LocalizedStringKey?
    @State private var query = ""

    var body: some View {
        NucleusSheetPage("Notes", onCancel: { dismiss() }) {
            searchField
            if let notes {
                let found = query.isEmpty ? notes : notes.filter(matches)
                if notes.isEmpty {
                    empty("note.text", title: "No notes to pick", message: "Write a note in Notes first. Hidden and locked notes aren't shared.")
                } else if found.isEmpty {
                    empty("magnifyingglass", title: "No matches", message: "No note matches that.")
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(found) { note in
                            row(note)
                            if note.id != found.last?.id { Divider().overlay(Nucleus.separator).padding(.leading, 40) }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: NucleusRadius.card, style: .continuous))
                    .nucleusGlass(cornerRadius: NucleusRadius.card)
                    .padding(.bottom, 24)
                }
            } else if let failure {
                empty("exclamationmark.triangle", title: "Couldn't load Notes", message: failure)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            }
        }
        .task { await load() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Nucleus.secondaryText)
            TextField("Search your notes", text: $query).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Nucleus.secondaryText) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .nucleusGlass(in: Capsule())
        .padding(.bottom, 22)
    }

    private func matches(_ note: SharedNote) -> Bool {
        [note.title, note.snippet, note.folder].contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    private func row(_ note: SharedNote) -> some View {
        Button {
            Haptics.success()
            onPick(note)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(NoteSection.color(note.color) ?? Nucleus.well)
                    .overlay(Circle().strokeBorder(Nucleus.separator))
                    .frame(width: 12, height: 12)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if note.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Nucleus.secondaryText)
                        }
                        Text(verbatim: note.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Nucleus.primaryText)
                            .lineLimit(1)
                    }
                    if let snippet = note.snippet, !snippet.isEmpty {
                        Text(verbatim: snippet)
                            .font(.system(size: 14))
                            .foregroundStyle(Nucleus.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let detail = detail(note) {
                        Text(verbatim: detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Nucleus.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if current?.noteId == note.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Nucleus.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    /// "Travel · 3 of 7 done".
    private func detail(_ note: SharedNote) -> String? {
        let checklist = note.checklist.map { String(localized: "\($0.done) of \($0.total) done") }
        let parts = [note.folder, checklist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func empty(_ icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        NucleusEmptyState(icon, title: title, message: message)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func load() async {
        do {
            notes = SharedNote.list(try await host.crossApp.view(app: NotesRefresh.app, name: "notes"))
        } catch CrossAppError.notSignedIn {
            failure = "Sign in with Nucleus ID to see your notes."
        } catch CrossAppError.scopeDenied {
            failure = "Turn the plugin off and on again to reconnect Notes."
        } catch CrossAppError.http(404, _) {
            failure = "Open Notes while signed in so it can share your notes."
        } catch {
            failure = "Check your connection and try again."
        }
    }
}
