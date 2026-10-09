import Foundation
import NotesPluginKit
import NucleusUI
import Observation
import SwiftUI

/// Talks to Todo for one note's cards: loads the `lists` view, sends checks and new tasks, and follows them
/// until Todo's view shows them. What it learns goes into the note's `pluginData` binding.
@MainActor
@Observable
final class TodoCardStore {
    /// Shown at once while a command is being sent, before Todo's command id is known.
    private(set) var sending: [PendingOp] = []
    private(set) var loading = false
    /// Why the last refresh failed; nil after one that worked.
    private(set) var failure: CrossAppError?
    /// When the view last loaded on this device.
    private(set) var fetchedAt: Date?

    @ObservationIgnored let host: any NotesHost
    /// At most one status request per command, and one view refresh, in this long.
    @ObservationIgnored let pollInterval: TimeInterval
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private var lastPoll: [String: Date] = [:]
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private let defaults: UserDefaults

    private static let fetchedKey = "todo-card.fetchedAt"

    init(host: any NotesHost, pollInterval: TimeInterval = 15, now: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard) {
        self.host = host
        self.pollInterval = pollInterval
        self.now = now
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.fetchedKey)
        fetchedAt = saved > 0 ? Date(timeIntervalSince1970: saved) : nil
    }

    #if DEBUG
    /// Previews show the offline footer without a failing network.
    func pretendOffline(since date: Date?) {
        failure = .network
        fetchedAt = date
    }
    #endif

    // MARK: Loading

    func refresh(_ value: Binding<JSONValue?>) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        lastRefresh = now()
        do {
            let lists = TodoList.lists(try await host.crossApp.view(app: TodoCardLogic.app, name: TodoCardLogic.view))
            update(value) { TodoCardLogic.refreshed($0, with: lists, now: now()) }
            failure = nil
            fetchedAt = now()
            defaults.set(fetchedAt!.timeIntervalSince1970, forKey: Self.fetchedKey)
        } catch let error as CrossAppError {
            failure = error
        } catch {
            failure = .network
        }
    }

    /// Asks where unsettled commands are (throttled), and looks at the view again once one is applied.
    func tick(_ value: Binding<JSONValue?>) async {
        for op in TodoCardLogic.unsettled(TodoCardData(value.wrappedValue)) {
            if let last = lastPoll[op.commandId], now().timeIntervalSince(last) < pollInterval { continue }
            lastPoll[op.commandId] = now()
            guard let command = try? await host.crossApp.status(op.commandId) else { continue }
            apply(command, to: value)
        }
        if TodoCardLogic.awaitingView(TodoCardData(value.wrappedValue)),
           lastRefresh.map({ now().timeIntervalSince($0) >= pollInterval }) ?? true {
            await refresh(value)
        }
    }

    /// Whether `tick` has anything to do.
    func isWaiting(_ value: JSONValue?) -> Bool { !TodoCardData(value).pending.isEmpty || !sending.isEmpty }

    // MARK: Commands

    func toggle(_ row: TaskRow, in list: AttachedList, _ value: Binding<JSONValue?>) async {
        // An added task isn't in Todo yet, so there's nothing to check off there.
        guard !row.isNew else { return }
        let done = !row.done
        let draft = PendingOp(commandId: "sending-\(UUID().uuidString)", kind: .setDone, listId: list.listId, taskId: row.id,
                              done: done, title: row.title, sentAt: Timestamp.string(now()))
        sending.removeAll { $0.kind == .setDone && $0.taskId == row.id }
        sending.append(draft)
        if done { Haptics.success() } else { Haptics.tap() }
        await send(draft, type: "setDone", payload: ["taskId": .string(row.id), "done": .bool(done)], value)
    }

    func add(_ title: String, to list: AttachedList, _ value: Binding<JSONValue?>) async {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let local = "sending-\(UUID().uuidString)"
        let draft = PendingOp(commandId: local, kind: .addTask, listId: list.listId, taskId: local, title: text,
                              sentAt: Timestamp.string(now()))
        sending.append(draft)
        Haptics.tap()
        var payload: [String: JSONValue] = ["title": .string(text)]
        if let id = list.listId { payload["listId"] = .string(id) }
        await send(draft, type: "addTask", payload: .object(payload), value)
    }

    private func send(_ draft: PendingOp, type: String, payload: JSONValue, _ value: Binding<JSONValue?>) async {
        defer { sending.removeAll { $0.commandId == draft.commandId } }
        do {
            let command = try await host.crossApp.send(app: TodoCardLogic.app, type: type, payload: payload)
            // Todo applies it on its next sync, so there's no point asking right away.
            lastPoll[command.id] = now()
            var op = draft
            op.commandId = command.id
            op.status = .pending
            if op.kind == .addTask { op.taskId = TodoCardLogic.taskID(forCommand: command.id) }
            update(value) { TodoCardLogic.record(op, in: $0) }
            if command.status != .pending { apply(command, to: value) }
        } catch CrossAppError.notSignedIn {
            host.show(String(localized: "Sign in with Nucleus ID to update Todo."), icon: "person.crop.circle.badge.exclamationmark")
        } catch CrossAppError.scopeDenied {
            host.show(String(localized: "Turn Todo card off and on again to reconnect Todo."), icon: "xmark.circle.fill")
        } catch {
            host.show(String(localized: "Couldn't reach Todo. Try again."), icon: "wifi.exclamationmark")
        }
    }

    func apply(_ command: CrossAppCommand, to value: Binding<JSONValue?>) {
        var rejected: PendingOp?
        update(value) {
            let result = TodoCardLogic.settled(command, in: $0, now: now())
            rejected = result.rejected
            return result.data
        }
        guard let op = rejected else { return }
        Haptics.error()
        let reason = command.result?["reason"]?.string
        switch (op.kind, reason) {
        case (.setDone, "taskNotFound"):
            host.show(String(localized: "“\(op.title)” isn't in Todo any more."), icon: "exclamationmark.triangle.fill")
        case (.setDone, _):
            host.show(String(localized: "Todo couldn't update “\(op.title)”."), icon: "exclamationmark.triangle.fill")
        case (.addTask, _):
            host.show(String(localized: "Todo couldn't add “\(op.title)”."), icon: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Attaching

    func remove(_ list: AttachedList, value: Binding<JSONValue?>, body: Binding<NoteBody>) {
        update(value) { TodoCardLogic.remove(list.id, from: $0) }
        let trimmed = TodoCardLogic.removingEmbeds(list.id, from: body.wrappedValue)
        if trimmed != body.wrappedValue { body.wrappedValue = trimmed }
    }

    /// Gives lists embedded in the body (e.g. on another device) a card.
    func adopt(_ body: NoteBody, _ value: Binding<JSONValue?>) {
        update(value) { TodoCardLogic.adopt(body, into: $0) }
    }

    /// Writes only a real change, so the note isn't edited by an idle refresh.
    private func update(_ value: Binding<JSONValue?>, _ change: (TodoCardData) -> TodoCardData) {
        let old = TodoCardData(value.wrappedValue)
        let new = change(old)
        if new != old { value.wrappedValue = new.json }
    }
}
