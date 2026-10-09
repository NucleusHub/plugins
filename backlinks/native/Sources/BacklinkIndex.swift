import Foundation
import NotesPluginKit

/// Which notes link to which: built once from all notes, then looked up per note.
struct BacklinkIndex: Sendable {
    /// A note that links to another.
    struct Source: Hashable, Sendable, Identifiable {
        let id: String
        let title: String
        /// The line that holds the link, to show where it's mentioned.
        let context: String
        let updatedAt: Date
        let hidden: Bool
    }

    private var sources: [String: [Source]] = [:]

    static let empty = BacklinkIndex(notes: [])

    init(notes: [PluginNote]) {
        for note in notes {
            var seen = Set<String>()
            for block in note.body.blocks where !block.type.isMedia {
                for run in block.runs {
                    guard let target = NoteLink.noteID(in: run.link), target != note.id, seen.insert(target).inserted else { continue }
                    let source = Source(id: note.id, title: note.displayTitle ?? String(localized: "New note"),
                                        context: Self.context(of: block), updatedAt: note.updatedAt, hidden: note.hidden)
                    sources[target, default: []].append(source)
                }
            }
        }
        for key in sources.keys { sources[key]?.sort { $0.updatedAt > $1.updatedAt } }
    }

    /// Notes linking to `noteID`, newest first. Hidden notes only count for a hidden note, so they never show outside the vault.
    func backlinks(to noteID: String, includeHidden: Bool) -> [Source] {
        let all = sources[noteID] ?? []
        return includeHidden ? all : all.filter { !$0.hidden }
    }

    func backlinks(to note: PluginNote) -> [Source] { backlinks(to: note.id, includeHidden: note.hidden) }

    private static func context(of block: Block, maxLength: Int = 120) -> String {
        let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// The current index for code that isn't on the main actor (note chips).
final class BacklinkSnapshot: @unchecked Sendable {
    static let shared = BacklinkSnapshot()
    private let lock = NSLock()
    private var stored: BacklinkIndex?

    var index: BacklinkIndex? { lock.withLock { stored } }
    func set(_ index: BacklinkIndex?) { lock.withLock { stored = index } }
}

/// Rebuilds the index after the notes change, debounced so a burst of edits builds it once.
@MainActor @Observable
final class BacklinkIndexer {
    static let shared = BacklinkIndexer()

    private(set) var index: BacklinkIndex?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration

    init(delay: Duration = .milliseconds(400)) {
        self.delay = delay
    }

    func notesChanged(_ notes: [PluginNote]) {
        pending?.cancel()
        pending = Task { [delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Off the main actor: a few thousand notes take a moment to walk.
            let built = await Task.detached(priority: .utility) { BacklinkIndex(notes: notes) }.value
            guard !Task.isCancelled else { return }
            self.install(built)
        }
    }

    /// The index, built now when nothing has been built yet.
    func index(for host: any NotesHost) -> BacklinkIndex {
        if let index { return index }
        let built = BacklinkIndex(notes: host.notes)
        install(built)
        return built
    }

    func reset() {
        pending?.cancel()
        install(nil)
    }

    private func install(_ index: BacklinkIndex?) {
        self.index = index
        BacklinkSnapshot.shared.set(index)
    }
}
