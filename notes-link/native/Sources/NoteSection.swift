import NucleusUI
import SwiftUI
import TodoPluginKit
import UIKit

/// The task editor's Note section: the linked note as a card, or ways to add one.
struct NoteSection: View {
    @Binding var value: JSONValue?
    @Binding var title: String
    @Binding var notes: String
    @Binding var color: String?
    let taskID: String
    let host: any TodoHost
    @State private var picking = false
    @State private var creating = false
    /// The linked note as Notes last published it, for the snippet and checklist.
    @State private var live: SharedNote?

    private var link: NoteLink? { NoteLink(value) }

    var body: some View {
        NucleusSection("Note") {
            if let link {
                card(link)
            } else {
                Button { picking = true } label: {
                    NucleusRow("Attach a note", subtitle: Text("Pick one from Notes"), icon: IconTile("note.text", tint: .amber)) { Chevron() }
                }
                .buttonStyle(NucleusRowButtonStyle())
                Button { Task { await create() } } label: {
                    NucleusRow("New note for this task", subtitle: Text("With the task's notes, linked back here"),
                               icon: IconTile("square.and.pencil", tint: .indigo)) {
                        if creating { ProgressView() }
                    }
                }
                .buttonStyle(NucleusRowButtonStyle())
                .disabled(creating)
            }
        }
        .sheet(isPresented: $picking) {
            NotePicker(host: host, current: link) { note in
                withAnimation(NucleusMotion.quick) {
                    live = note
                    value = NoteLink(noteId: note.id, title: note.displayTitle, color: note.color).json
                    // Only on attach: later color changes on either side stay separate.
                    if NoteColor(note.color) != nil { color = note.color }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .task(id: link?.noteId) { await loadLive() }
    }

    // MARK: Card

    private func card(_ link: NoteLink) -> some View {
        let tint = NoteSection.color(link.color)
        let note = live?.id == link.noteId ? live : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint ?? Nucleus.accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: note?.displayTitle ?? link.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nucleus.primaryText)
                        .lineLimit(2)
                    if let snippet = note?.snippet, !snippet.isEmpty {
                        Text(verbatim: snippet)
                            .font(.system(size: 14))
                            .foregroundStyle(Nucleus.secondaryText)
                            .lineLimit(3)
                    }
                    if let folder = note?.folder {
                        Label { Text(verbatim: folder) } icon: { Image(systemName: "folder") }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Nucleus.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                menu
            }
            if let checklist = note?.checklist { progress(checklist, tint: tint ?? Nucleus.accent) }
            status(link)
            Button { open(link) } label: {
                Label("Open in Notes", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .nucleusGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background {
            if let tint {
                LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    private var menu: some View {
        Menu {
            Button { picking = true } label: { Label("Change", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) {
                withAnimation(NucleusMotion.quick) { value = nil }
            } label: { Label("Remove", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Nucleus.glyph)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Nucleus.well))
        }
        .accessibilityLabel("More")
    }

    private func progress(_ checklist: SharedNote.Checklist, tint: Color) -> some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                Capsule().fill(Nucleus.well)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).frame(width: geo.size.width * CGFloat(min(checklist.done, checklist.total)) / CGFloat(checklist.total))
                    }
            }
            .frame(height: 6)
            Text("\(checklist.done) of \(checklist.total) done")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func status(_ link: NoteLink) -> some View {
        if link.missing == true {
            Label("This note isn't shared anymore — it may be hidden, locked, or deleted.", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Nucleus.danger)
        } else if link.pending != nil {
            Label("Waiting for Notes to sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Nucleus.accent)
        }
    }

    // MARK: Actions

    private func open(_ link: NoteLink) {
        guard let url = link.url, UIApplication.shared.canOpenURL(url) else {
            host.show(String(localized: "Install Notes to open it"), icon: "note.text")
            return
        }
        UIApplication.shared.open(url)
    }

    private func create() async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            host.show(String(localized: "Give the task a title first."), icon: "character.cursor.ibeam")
            return
        }
        creating = true
        defer { creating = false }
        do {
            let command = try await host.crossApp.send(app: NotesRefresh.app, type: "createNote",
                                                       payload: NoteLink.createPayload(title: name, text: notes, taskID: taskID))
            Haptics.success()
            withAnimation(NucleusMotion.quick) {
                value = NoteLink(noteId: NoteLink.noteID(forCommand: command.id), title: name, pending: .init(commandId: command.id)).json
            }
            host.show(String(localized: "Created in Notes. It appears there on its next sync."), icon: "note.text")
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to create notes."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Turn the plugin off and on again to reconnect Notes."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't reach Notes. Try again."), icon: "wifi.exclamationmark")
        }
    }

    private func loadLive() async {
        guard let id = link?.noteId, live?.id != id,
              let value = try? await host.crossApp.view(app: NotesRefresh.app, name: "notes") else { return }
        live = SharedNote.list(value).first { $0.id == id }
    }

    /// A note's color as Notes stores it, in NucleusUI's palette.
    static func color(_ raw: String?) -> Color? {
        switch NoteColor(raw) {
        case .tint(let name): NucleusTint(rawValue: name)?.color
        case .hex(let value): Color(hex: value)
        case nil: nil
        }
    }
}
