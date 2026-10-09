import Foundation
import NotesPluginKit

/// Saves a version when a note's text changes, at most one per note every `interval`.
/// What it saves is the state *before* the change: the end of the last editing burst.
@MainActor
final class HistoryRecorder {
    static let shared = HistoryRecorder(store: .shared)

    let store: HistoryStore
    let interval: TimeInterval
    let pruneInterval: TimeInterval
    var now: () -> Date

    private struct Seen {
        let updatedAt: Date
        let title: String
        let body: NoteBody
    }

    private var seen: [String: Seen] = [:]
    private var lastSaved: [String: Date] = [:]
    private var lastPrune: Date?

    init(store: HistoryStore, interval: TimeInterval = 120, pruneInterval: TimeInterval = 600, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.interval = interval
        self.pruneInterval = pruneInterval
        self.now = now
    }

    func notesChanged(_ notes: [PluginNote]) {
        let time = now()
        for note in notes {
            // Vault notes never reach the disk unencrypted; a note just moved there loses its history.
            if note.hidden {
                if seen.removeValue(forKey: note.id) != nil || store.hasHistory(note.id) { store.delete(note.id) }
                lastSaved[note.id] = nil
                continue
            }
            let current = Seen(updatedAt: note.updatedAt, title: note.title, body: note.body)
            guard let previous = seen.updateValue(current, forKey: note.id) else { continue }
            guard previous.updatedAt != note.updatedAt, previous.title != note.title || previous.body != note.body else { continue }
            capture(noteID: note.id, title: previous.title, body: previous.body, at: time, throttled: true)
        }
        pruneIfDue(notes, at: time)
    }

    /// Saves the note as it is now, whatever the interval (before a restore).
    func saveNow(_ note: PluginNote) {
        guard !note.hidden else { return }
        capture(noteID: note.id, title: note.title, body: note.body, at: now(), throttled: false)
    }

    func forget() {
        seen = [:]
        lastSaved = [:]
        lastPrune = nil
    }

    private func capture(noteID: String, title: String, body: NoteBody, at time: Date, throttled: Bool) {
        // A brand-new note's empty start isn't worth a version.
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !body.isEmpty else { return }
        let latest = store.latest(of: noteID)
        if throttled, let last = lastSaved[noteID] ?? latest?.savedAt, time.timeIntervalSince(last) < interval { return }
        if let latest, latest.title == title, latest.body == body { return }
        store.save(NoteVersion(savedAt: time, title: title, body: body), noteID: noteID)
        lastSaved[noteID] = time
    }

    private func pruneIfDue(_ notes: [PluginNote], at time: Date) {
        // An empty list is more likely "not loaded yet" than "everything deleted".
        guard !notes.isEmpty, lastPrune.map({ time.timeIntervalSince($0) >= pruneInterval }) ?? true else { return }
        lastPrune = time
        store.prune(keeping: Set(notes.filter { !$0.hidden }.map(\.id)))
    }
}
