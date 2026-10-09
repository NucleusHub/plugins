import Foundation
import NotesPluginKit
import Observation

/// The word ledger in a JSON file on this device, updated a moment after the notes stop changing.
@MainActor
@Observable
public final class LedgerStore {
    public static let shared = LedgerStore()
    public static let debounce: Duration = .seconds(2)

    public private(set) var ledger = WordLedger()
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(fileURL: URL = LedgerStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(WordLedger.self, from: data) {
            ledger = saved
        }
    }

    public nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plugins/writing-stats/word-ledger.json")
    }

    /// Typing fires this on every autosave; only the last call in a burst counts.
    public func notesChanged(host: any NotesHost, delay: Duration = LedgerStore.debounce) {
        pending?.cancel()
        pending = Task { [weak self, weak host] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let host else { return }
            self.record(host.notes)
        }
    }

    public func record(_ notes: [PluginNote], now: Date = Date(), days: Days = Days()) {
        // Hidden notes stay out of the ledger, like everywhere else outside the vault.
        let counts = Dictionary(notes.filter { !$0.hidden }.map { ($0.id, $0.body.wordCount) }, uniquingKeysWith: max)
        ledger.record(counts, day: days.key(now))
        save()
    }

    public func reset() {
        pending?.cancel()
        ledger = WordLedger()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(ledger).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Word ledger not saved: \(error)")
        }
    }
}
