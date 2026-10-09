import Foundation
import TodoPluginKit

/// Keeps linked notes' titles and colors in step with Notes' view, at most once per `interval`.
@MainActor
public final class NotesRefresh {
    public static let shared = NotesRefresh()
    public nonisolated static let pluginID = "notes-link"
    nonisolated static let app = "notes"

    let interval: TimeInterval
    let now: () -> Date
    private var last: Date?
    private var running: Task<Void, Never>?

    public init(interval: TimeInterval = 600, now: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.now = now
    }

    public func refresh(_ host: any TodoHost) {
        guard running == nil, host.tasks.contains(where: { $0.pluginData[Self.pluginID] != nil }) else { return }
        if let last, now().timeIntervalSince(last) < interval { return }
        last = now()
        running = Task { [weak self] in
            await self?.run(host)
            self?.running = nil
        }
    }

    /// Waits for a running refresh; for tests.
    public func idle() async { await running?.value }

    func forget() { last = nil }

    private func run(_ host: any TodoHost) async {
        guard let value = try? await host.crossApp.view(app: Self.app, name: "notes") else { return }
        let notes = SharedNote.byID(SharedNote.list(value))
        for task in host.tasks {
            guard let link = NoteLink(task.pluginData[Self.pluginID]) else { continue }
            var new = link.refreshed(with: notes)
            // A note that never arrives: Notes refused or dropped the command.
            if let pending = new.pending, let command = try? await host.crossApp.status(pending.commandId),
               command.status == .rejected || command.status == .cancelled {
                new.pending = nil
                new.missing = true
            }
            // Written only over what the step started from, so an edit made meanwhile wins.
            guard new != link, NoteLink(host.tasks.first(where: { $0.id == task.id })?.pluginData[Self.pluginID]) == link else { continue }
            host.setPluginData(taskID: task.id, pluginID: Self.pluginID, value: new.json)
        }
    }
}
