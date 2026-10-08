import Foundation
import TodoPluginKit

/// Carries out `Reconciler` steps for linked tasks. Level-triggered: every `tasksChanged` looks at all of
/// them, so completions from widgets, Siri or another device are picked up the same way.
@MainActor
public final class LinkSync {
    public static let shared = LinkSync()
    public nonisolated static let pluginID = "watchlist-link"
    nonisolated static let app = "watchlist"

    /// At most one status request per command in this long.
    let pollInterval: TimeInterval
    let now: () -> Date
    private var running: [String: Task<Void, Never>] = [:]
    private var lastPoll: [String: Date] = [:]
    private var recheck: Task<Void, Never>?
    private weak var host: (any TodoHost)?

    public init(pollInterval: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.pollInterval = pollInterval
        self.now = now
    }

    public func reconcile(_ host: any TodoHost) {
        self.host = host
        for task in host.tasks where task.pluginData[Self.pluginID] != nil && running[task.id] == nil {
            let id = task.id
            running[id] = Task { [weak self] in
                await self?.run(id, host: host)
                self?.running[id] = nil
            }
        }
    }

    /// Waits for every task's steps to finish; for tests.
    public func idle() async {
        while let task = running.values.first { await task.value }
    }

    private func current(_ taskID: String, in host: any TodoHost) -> (task: PluginTask, link: WatchLink)? {
        guard let task = host.tasks.first(where: { $0.id == taskID }), let link = WatchLink(task.pluginData[Self.pluginID]) else { return nil }
        return (task, link)
    }

    /// Writes `new` only if the link is still what the step started from, so an edit made meanwhile wins.
    private func store(_ new: WatchLink, over old: WatchLink, _ taskID: String, host: any TodoHost) {
        guard current(taskID, in: host)?.link == old, new != old else { return }
        host.setPluginData(taskID: taskID, pluginID: Self.pluginID, value: new.json)
    }

    /// Steps one task until it needs nothing more; a failed request is retried on the next change.
    private func run(_ taskID: String, host: any TodoHost) async {
        let client = host.crossApp
        // Bounded: each pass either stores something or stops.
        for _ in 0..<8 {
            guard let (task, link) = current(taskID, in: host) else { return }
            do {
                switch Reconciler.step(done: task.done, link: link) {
                case .none:
                    return
                case .update(let new):
                    store(new, over: link, taskID, host: host)
                case .sendMark(let payload):
                    let command = try await client.send(app: Self.app, type: "markWatched", payload: payload)
                    // Watchlist applies it on its next sync, so there's no point asking right away.
                    lastPoll[command.id] = now()
                    store(Reconciler.marked(link, command), over: link, taskID, host: host)
                case .poll(let id):
                    if let last = lastPoll[id], now().timeIntervalSince(last) < pollInterval {
                        scheduleRecheck()
                        return
                    }
                    lastPoll[id] = now()
                    let new = Reconciler.polled(link, try await client.status(id))
                    store(new, over: link, taskID, host: host)
                    if new.broken != nil, link.broken == nil {
                        host.show(String(localized: "Watchlist couldn't mark “\(link.title)” watched."), icon: "exclamationmark.triangle.fill")
                    }
                    if new == link { scheduleRecheck(); return }
                case .confirm:
                    guard let mark = link.mark else { return }
                    // A fresh look first: the mark may have landed, and then the library says whether a rollback is safe.
                    if !mark.status.isSettled, let command = try? await client.status(mark.id) {
                        lastPoll[mark.id] = now()
                        let new = Reconciler.polled(link, command)
                        if new != link { store(new, over: link, taskID, host: host); continue }
                    }
                    if mark.status == .applied, let library = try? await client.view(app: Self.app, name: "library"),
                       Reconciler.watchedPast(link, in: LibraryTitle.library(library)) {
                        store(Reconciler.justTheTask(link), over: link, taskID, host: host)
                        host.show(String(localized: "You've watched past \(link.range ?? link.title) since. Watchlist is left as it is."), icon: "tv")
                        continue
                    }
                    let choice = await host.confirm(
                        title: String(localized: "Also mark “\(link.label)” unwatched?"),
                        message: String(localized: "Finishing this task marked it watched in Watchlist."),
                        actions: [String(localized: "Just the task"), String(localized: "Also mark unwatched")]
                    )
                    // Done again, or edited, while the dialog was up: the answer no longer applies.
                    guard let fresh = current(taskID, in: host), fresh.link == link, !fresh.task.done else { continue }
                    if choice == 1 {
                        let outcome = try await client.cancel(mark.id)
                        // A fresh look at a mark that turned out applied, so "unwatch" doesn't wait out the throttle.
                        lastPoll[mark.id] = nil
                        store(Reconciler.cancelled(link, outcome), over: link, taskID, host: host)
                    } else {
                        store(Reconciler.justTheTask(link), over: link, taskID, host: host)
                    }
                case .sendUnmark(let payload):
                    _ = try await client.send(app: Self.app, type: "unmarkWatched", payload: payload)
                    store(Reconciler.unmarked(link), over: link, taskID, host: host)
                }
            } catch {
                return
            }
        }
    }

    /// Looks again later while a mark is on its way, even when nothing else changes.
    private func scheduleRecheck() {
        guard recheck == nil else { return }
        recheck = Task { [weak self, pollInterval] in
            try? await Task.sleep(for: .seconds(pollInterval))
            guard let self else { return }
            recheck = nil
            if let host { reconcile(host) }
        }
    }
}
