import NotesPluginKit
import SwiftUI
import XCTest
@testable import TodoCardPlugin

@MainActor
final class TodoCardStoreTests: XCTestCase {
    private final class Box { var value: JSONValue? }

    private var box = Box()
    private var value: Binding<JSONValue?> { Binding(get: { self.box.value }, set: { self.box.value = $0 }) }
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private var data: TodoCardData { TodoCardData(box.value) }

    private func make(_ host: FakeNotesHost) -> TodoCardStore {
        TodoCardStore(host: host, pollInterval: 10, now: { [unowned self] in clock }, defaults: UserDefaults(suiteName: "todo-card-tests")!)
    }

    override func setUp() {
        box = Box()
        box.value = TodoCardLogic.attach(TodoSamples.groceries, to: TodoCardData(), now: clock).json
    }

    func testCheckingOffSendsSetDoneAndKeepsItPending() async throws {
        let host = TodoSamples.host()
        let store = make(host)
        let list = data.lists[0]
        let row = try XCTUnwrap(TodoCardLogic.rows(list, pending: []).first { $0.id == "t1" })
        await store.toggle(row, in: list, value)

        let sent = try XCTUnwrap(host.client.sent.first)
        XCTAssertEqual(sent.type, "setDone")
        XCTAssertEqual(sent.payload, ["taskId": "t1", "done": true])
        XCTAssertEqual(data.pending.map(\.commandId), [sent.id])
        XCTAssertTrue(store.sending.isEmpty)
        XCTAssertTrue(TodoCardLogic.rows(data.lists[0], pending: data.pending).first { $0.id == "t1" }!.done)
    }

    func testARejectedCheckSnapsBackWithAMessage() async throws {
        let host = TodoSamples.host()
        let store = make(host)
        let list = data.lists[0]
        let row = try XCTUnwrap(TodoCardLogic.rows(list, pending: []).first { $0.id == "t1" })
        await store.toggle(row, in: list, value)
        let id = try XCTUnwrap(host.client.sent.first?.id)
        host.client.statuses[id] = CrossAppCommand(id: id, type: "setDone", status: .rejected, result: ["reason": "taskNotFound"])

        await store.tick(value)
        XCTAssertEqual(data.pending.count, 1, "throttled: no status request right after sending")

        clock += 11
        await store.tick(value)
        XCTAssertTrue(data.pending.isEmpty)
        XCTAssertEqual(host.toasts, ["“Oat milk” isn't in Todo any more."])
        XCTAssertFalse(TodoCardLogic.rows(data.lists[0], pending: data.pending).first { $0.id == "t1" }!.done)
    }

    func testAnAddedTaskWaitsForTheViewThenSettles() async throws {
        let host = TodoSamples.host()
        let store = make(host)
        await store.add("  Lemons  ", to: data.lists[0], value)

        let sent = try XCTUnwrap(host.client.sent.first)
        XCTAssertEqual(sent.payload, ["title": "Lemons", "listId": "a1b2c3d4e5f6a1b2c3d4e5f6"])
        let taskID = TodoCardLogic.taskID(forCommand: sent.id)
        XCTAssertEqual(data.pending.first?.taskId, taskID)
        XCTAssertEqual(TodoCardLogic.rows(data.lists[0], pending: data.pending).first?.title, "Lemons")

        // Todo applied it and published a view with the task.
        host.client.statuses[sent.id] = CrossAppCommand(id: sent.id, type: "addTask", status: .applied, result: ["taskId": .string(taskID)])
        var groceries = TodoSamples.groceries
        groceries.tasks.insert(TodoTask(id: taskID, title: "Lemons"), at: 0)
        host.client.views["todo/lists"] = TodoSamples.view([TodoSamples.inbox, groceries])
        clock += 11
        await store.tick(value)
        XCTAssertTrue(data.pending.isEmpty)
        XCTAssertEqual(data.lists[0].tasks.first?.id, taskID)
        XCTAssertTrue(host.toasts.isEmpty)
    }

    func testOfflineSendTellsThePersonAndKeepsNothing() async throws {
        let host = TodoSamples.host()
        host.client.failSends = .network
        let store = make(host)
        await store.add("Lemons", to: data.lists[0], value)
        XCTAssertTrue(data.pending.isEmpty)
        XCTAssertTrue(store.sending.isEmpty)
        XCTAssertEqual(host.toasts, ["Couldn't reach Todo. Try again."])
    }

    func testOfflineRefreshKeepsTheCachedTasks() async {
        let host = TodoSamples.host()
        host.client.failViews = .network
        let store = make(host)
        let before = box.value
        await store.refresh(value)
        XCTAssertEqual(store.failure, .network)
        XCTAssertEqual(box.value, before)
    }

    func testActivationAsksForTheScopes() async {
        let host = TodoSamples.host()
        let ok = await TodoCardPlugin().activate(host: host)
        XCTAssertTrue(ok)
        XCTAssertEqual(TodoCardPlugin().manifest.id, "todo-card")
    }
}
