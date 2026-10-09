import NotesPluginKit
import XCTest
@testable import TodoCardPlugin

final class TodoCardLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var nowString: String { Timestamp.string(now) }

    private func list(_ id: String?, _ tasks: [TodoTask], name: String = "Groceries") -> TodoList {
        TodoList(listId: id, name: name, icon: "cart", tint: "emerald", tasks: tasks)
    }

    // MARK: Decoding

    func testDecodesTheListsViewLeniently() throws {
        let json = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"lists":[
          {"id":null,"name":"Inbox","icon":"tray","tint":"indigo","color":null,"tasks":[
            {"id":"a","title":"Call mom","done":false,"due":"2027-01-15","time":"09:30","priority":2,"flagged":true,"completedAt":null}]},
          {"id":"l1","name":"Groceries","icon":"cart","tint":"emerald","color":null,"tasks":[
            {"id":"b","title":"Milk","done":true,"completedAt":"2027-01-14T10:00:00.000Z","extra":1},
            {"title":"no id, skipped"},
            {"id":"c","priority":9}]},
          "not a list",
          {"id":"","name":""}
        ]}
        """.utf8))
        let lists = TodoList.lists(json)
        XCTAssertEqual(lists.map(\.id), ["inbox", "l1", "inbox"])
        XCTAssertEqual(lists[0].tasks.first?.due, "2027-01-15")
        XCTAssertEqual(lists[0].tasks.first?.time, "09:30")
        XCTAssertEqual(lists[0].tasks.first?.priority, 2)
        XCTAssertTrue(lists[0].tasks.first?.flagged ?? false)
        XCTAssertEqual(lists[1].tasks.map(\.id), ["b", "c"], "a task without an id is skipped")
        XCTAssertEqual(lists[1].tasks[1].priority, 3, "priority is clamped")
        XCTAssertEqual(lists[1].tasks[1].title, "")
        XCTAssertEqual(lists[1].openCount, 1)
        XCTAssertEqual(lists[2].name, "Inbox", "an empty id is the Inbox")
        XCTAssertEqual(TodoList.lists(.null), [])
    }

    func testDataRoundTripsAndEmptyIsNil() {
        var data = TodoCardLogic.attach(list(nil, [TodoTask(id: "a", title: "A")], name: "Inbox"), to: TodoCardData(), now: now)
        data.pending = [PendingOp(commandId: "c", kind: .setDone, listId: nil, taskId: "a", done: true, title: "A", sentAt: nowString)]
        XCTAssertEqual(TodoCardData(data.json), data)
        XCTAssertNil(data.json?["lists"]?.array?.first?["listId"], "the Inbox has no list id")
        XCTAssertNil(TodoCardData().json)
        XCTAssertEqual(TodoCardData(.string("junk")), TodoCardData())
    }

    // MARK: Attaching

    func testSnapshotKeepsOpenFirstAndCapsBoth() {
        let open = (0..<60).map { TodoTask(id: "o\($0)", title: "Open \($0)") }
        let done = (0..<15).map { TodoTask(id: "d\($0)", title: "Done \($0)", done: true, completedAt: "2027-01-\(String(format: "%02d", $0 + 1))T00:00:00.000Z") }
        let snap = TodoCardLogic.snapshot(list("l", done + open), syncedAt: nil)
        XCTAssertEqual(snap.tasks.count, TodoCardLogic.maxOpen + TodoCardLogic.maxDone)
        XCTAssertEqual(snap.tasks.first?.id, "o0")
        XCTAssertEqual(snap.tasks[TodoCardLogic.maxOpen].id, "d14", "latest done first")
        XCTAssertEqual(snap.open, 60)
        let rows = TodoCardLogic.rows(snap, pending: [])
        XCTAssertEqual(TodoCardLogic.openCount(snap, rows: rows), 60, "counts open tasks past the cap")
    }

    func testEmbedBlockAdoptAndRemove() {
        let groceries = list("l1", [TodoTask(id: "a", title: "A")])
        let block = TodoCardLogic.embedBlock(for: groceries)
        XCTAssertEqual(block.type, .embed)
        XCTAssertEqual(block.plugin, "todo-card")
        XCTAssertEqual(block.ref?["listId"]?.string, "l1")
        XCTAssertEqual(block.ref?["name"]?.string, "Groceries")
        let inbox = TodoCardLogic.embedBlock(for: list(nil, [], name: "Inbox"))
        XCTAssertEqual(inbox.ref?["listId"], .null)

        let body = NoteBody(blocks: [Block(text: "Hi"), block, inbox, Block(.embed, plugin: "other", ref: ["listId": "l1"])])
        let adopted = TodoCardLogic.adopt(body, into: TodoCardData())
        XCTAssertEqual(adopted.lists.map(\.id), ["l1", "inbox"])
        XCTAssertEqual(adopted.lists.map(\.name), ["Groceries", "Inbox"])
        XCTAssertEqual(TodoCardLogic.adopt(body, into: adopted), adopted, "adopting twice changes nothing")

        let trimmed = TodoCardLogic.removingEmbeds("l1", from: body)
        XCTAssertEqual(trimmed.blocks.count, 3)
        XCTAssertTrue(trimmed.blocks.contains { $0.plugin == "other" }, "other plugins' embeds stay")
    }

    func testRemoveDropsTheListAndItsPendingCommands() {
        var data = TodoCardLogic.attach(list("l1", [TodoTask(id: "a", title: "A")]), to: TodoCardData(), now: now)
        data = TodoCardLogic.attach(list("l2", [TodoTask(id: "b", title: "B")], name: "Other"), to: data, now: now)
        data.pending = [
            PendingOp(commandId: "c1", kind: .setDone, listId: "l1", taskId: "a", done: true, title: "A", sentAt: nowString),
            PendingOp(commandId: "c2", kind: .setDone, listId: "l2", taskId: "b", done: true, title: "B", sentAt: nowString),
        ]
        let removed = TodoCardLogic.remove("l1", from: data)
        XCTAssertEqual(removed.lists.map(\.id), ["l2"])
        XCTAssertEqual(removed.pending.map(\.commandId), ["c2"])
    }

    // MARK: Optimistic state

    func testRowsLayPendingCommandsOverTheView() {
        let attached = TodoCardLogic.snapshot(list("l1", [
            TodoTask(id: "a", title: "A"), TodoTask(id: "b", title: "B", done: true),
        ]), syncedAt: nil)
        let pending = [
            PendingOp(commandId: "c1", kind: .setDone, listId: "l1", taskId: "a", done: true, title: "A", sentAt: nowString),
            PendingOp(commandId: "c2", kind: .addTask, listId: "l1", taskId: "n", title: "New", sentAt: nowString),
            PendingOp(commandId: "c3", kind: .addTask, listId: "other", taskId: "m", title: "Elsewhere", sentAt: nowString),
        ]
        let rows = TodoCardLogic.rows(attached, pending: pending)
        XCTAssertEqual(rows.map(\.id), ["n", "a", "b"])
        XCTAssertTrue(rows[0].isNew && rows[0].pending)
        XCTAssertTrue(rows[1].done && rows[1].pending)
        XCTAssertFalse(rows[1].inDoneSection, "a pending check stays in place until Todo confirms")
        XCTAssertTrue(rows[2].inDoneSection)
        let progress = TodoCardLogic.progress(attached, rows: rows)
        XCTAssertEqual(progress.done, 2)
        XCTAssertEqual(progress.total, 3)
    }

    func testANewerCheckReplacesTheOlderOne() {
        var data = TodoCardData()
        data = TodoCardLogic.record(PendingOp(commandId: "c1", kind: .setDone, listId: nil, taskId: "a", done: true, title: "A", sentAt: nowString), in: data)
        data = TodoCardLogic.record(PendingOp(commandId: "c2", kind: .setDone, listId: nil, taskId: "a", done: false, title: "A", sentAt: nowString), in: data)
        XCTAssertEqual(data.pending.map(\.commandId), ["c2"])
    }

    func testFreshViewConfirmsAndExpiresCommands() {
        var data = TodoCardLogic.attach(list("l1", [TodoTask(id: "a", title: "A"), TodoTask(id: "b", title: "B")]), to: TodoCardData(), now: now)
        let old = Timestamp.string(now.addingTimeInterval(-TodoCardLogic.appliedGrace - 1))
        data.pending = [
            PendingOp(commandId: "c1", kind: .setDone, listId: "l1", taskId: "a", done: true, title: "A", status: .applied, sentAt: nowString, settledAt: nowString),
            PendingOp(commandId: "c2", kind: .setDone, listId: "l1", taskId: "b", done: true, title: "B", status: .applied, sentAt: nowString, settledAt: nowString),
            PendingOp(commandId: "c3", kind: .addTask, listId: "l1", taskId: "n", title: "New", sentAt: nowString),
            PendingOp(commandId: "c4", kind: .addTask, listId: "l1", taskId: "m", title: "Late", status: .applied, sentAt: old, settledAt: old),
            PendingOp(commandId: "c5", kind: .setDone, listId: "l1", taskId: "gone", done: true, title: "Gone", status: .applied, sentAt: nowString, settledAt: nowString),
        ]
        let fresh = list("l1", [
            TodoTask(id: "a", title: "A", done: true), TodoTask(id: "b", title: "B"), TodoTask(id: "n", title: "New"),
        ])
        let out = TodoCardLogic.refreshed(data, with: [fresh], now: now.addingTimeInterval(60))
        // c1: view shows it. c3: the task arrived. c4: applied too long ago. c5: applied and the task left the view.
        XCTAssertEqual(out.pending.map(\.commandId), ["c2"])
        XCTAssertEqual(out.lists[0].tasks.map(\.id), ["b", "n", "a"])
        XCTAssertEqual(out.lists[0].open, 2)
    }

    func testRefreshStampsOnlyRealChangesAndMarksMissingLists() {
        let groceries = list("l1", [TodoTask(id: "a", title: "A")])
        let data = TodoCardLogic.attach(groceries, to: TodoCardData(), now: now)
        let later = now.addingTimeInterval(600)
        XCTAssertEqual(TodoCardLogic.refreshed(data, with: [groceries], now: later), data, "same view, same data")

        var changed = groceries
        changed.tasks.append(TodoTask(id: "b", title: "B"))
        XCTAssertEqual(TodoCardLogic.refreshed(data, with: [changed], now: later).lists[0].syncedAt, Timestamp.string(later))

        let gone = TodoCardLogic.refreshed(data, with: [], now: later)
        XCTAssertEqual(gone.lists[0].missing, true)
        XCTAssertEqual(gone.lists[0].tasks, data.lists[0].tasks, "keeps what it last saw")
        XCTAssertNil(TodoCardLogic.refreshed(gone, with: [groceries], now: later).lists[0].missing, "back again")
    }

    func testSettledTracksStatusAndDropsRejected() {
        var data = TodoCardData()
        data.pending = [
            PendingOp(commandId: "c1", kind: .setDone, listId: nil, taskId: "a", done: true, title: "A", sentAt: nowString),
            PendingOp(commandId: "c2", kind: .addTask, listId: nil, taskId: "x", title: "B", sentAt: nowString),
        ]
        let delivered = TodoCardLogic.settled(CrossAppCommand(id: "c1", type: "setDone", status: .delivered), in: data, now: now)
        XCTAssertEqual(delivered.data.pending[0].status, .delivered)
        XCTAssertNil(delivered.data.pending[0].settledAt)

        let rejected = TodoCardLogic.settled(CrossAppCommand(id: "c1", type: "setDone", status: .rejected, result: ["reason": "taskNotFound"]),
                                             in: delivered.data, now: now)
        XCTAssertEqual(rejected.rejected?.commandId, "c1")
        XCTAssertEqual(rejected.data.pending.map(\.commandId), ["c2"])

        let applied = TodoCardLogic.settled(CrossAppCommand(id: "c2", type: "addTask", status: .applied, result: ["taskId": "real"]),
                                            in: rejected.data, now: now)
        XCTAssertNil(applied.rejected)
        XCTAssertEqual(applied.data.pending[0].status, .applied)
        XCTAssertEqual(applied.data.pending[0].taskId, "real", "trusts Todo's task id")
        XCTAssertEqual(applied.data.pending[0].settledAt, nowString)
        XCTAssertTrue(TodoCardLogic.awaitingView(applied.data))
        XCTAssertTrue(TodoCardLogic.unsettled(applied.data).isEmpty)

        let unknown = TodoCardLogic.settled(CrossAppCommand(id: "zzz", type: "setDone", status: .applied), in: data, now: now)
        XCTAssertEqual(unknown.data, data)
    }

    func testTaskIDMatchesTodosDerivation() {
        // Todo: first 24 hex of sha256(command id); sha256("abc") starts ba7816bf8f01cfea414140de.
        XCTAssertEqual(TodoCardLogic.taskID(forCommand: "abc"), "ba7816bf8f01cfea414140de")
    }

    // MARK: Text

    func testChipShareAndSearchText() {
        var data = TodoCardLogic.attach(list("l1", [
            TodoTask(id: "a", title: "Milk"), TodoTask(id: "b", title: "Eggs"), TodoTask(id: "c", title: "Tea", done: true),
        ]), to: TodoCardData(), now: now)
        XCTAssertEqual(TodoCardLogic.chip(data), NoteChip(icon: "checklist", text: "Groceries · 2 left"))
        XCTAssertEqual(TodoCardLogic.shareText(data), "- [ ] Milk\n- [ ] Eggs")
        XCTAssertEqual(TodoCardLogic.searchText(data), "Groceries Milk Eggs Tea")

        data.pending = [PendingOp(commandId: "c1", kind: .setDone, listId: "l1", taskId: "a", done: true, title: "Milk", sentAt: nowString)]
        XCTAssertEqual(TodoCardLogic.chip(data)?.text, "Groceries · 1 left", "pending checks count")

        data = TodoCardLogic.attach(list(nil, [TodoTask(id: "i", title: "Call", done: true)], name: "Inbox"), to: data, now: now)
        XCTAssertEqual(TodoCardLogic.chip(data)?.text, "Groceries +1 · 1 left")
        XCTAssertEqual(TodoCardLogic.shareText(data), "- [ ] Eggs", "lists with nothing open are left out")

        let done = TodoCardLogic.attach(list("l", [TodoTask(id: "a", title: "A", done: true)]), to: TodoCardData(), now: now)
        XCTAssertEqual(TodoCardLogic.chip(done)?.text, "Groceries · All done")
        XCTAssertNil(TodoCardLogic.shareText(done))
        XCTAssertNil(TodoCardLogic.chip(TodoCardData()))
    }

    func testShareTextGroupsSeveralLists() {
        var data = TodoCardLogic.attach(list("l1", [TodoTask(id: "a", title: "Milk")]), to: TodoCardData(), now: now)
        data = TodoCardLogic.attach(list("l2", [TodoTask(id: "b", title: "Passport")], name: "Trip"), to: data, now: now)
        XCTAssertEqual(TodoCardLogic.shareText(data), "Groceries:\n- [ ] Milk\n\nTrip:\n- [ ] Passport")
    }

    func testURLs() {
        XCTAssertEqual(TodoCardLogic.url(listId: "abc").absoluteString, "com.nucleushome.todo://list/abc")
        XCTAssertEqual(TodoCardLogic.url(listId: nil).absoluteString, "com.nucleushome.todo://list/inbox")
    }

    func testDueLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        let noon = calendar.date(from: DateComponents(year: 2027, month: 3, day: 10, hour: 12))!
        func label(_ due: String?, _ time: String? = nil) -> String? { TodoCardLogic.dueLabel(due: due, time: time, now: noon, calendar: calendar)?.text }
        func overdue(_ due: String, _ time: String? = nil) -> Bool? { TodoCardLogic.dueLabel(due: due, time: time, now: noon, calendar: calendar)?.overdue }
        XCTAssertEqual(label("2027-03-10"), "Today")
        XCTAssertEqual(label("2027-03-11"), "Tomorrow")
        XCTAssertEqual(label("2027-03-09"), "Yesterday")
        XCTAssertEqual(label("2027-03-13"), "Sat")
        XCTAssertEqual(label("2027-04-02"), "Apr 2")
        XCTAssertEqual(label("2028-04-02"), "Apr 2, 2028")
        XCTAssertEqual(label("2027-03-10", "09:30"), "Today 09:30")
        XCTAssertNil(label(nil))
        XCTAssertNil(label("soon"))
        XCTAssertEqual(overdue("2027-03-09"), true)
        XCTAssertEqual(overdue("2027-03-10"), false)
        XCTAssertEqual(overdue("2027-03-10", "09:30"), true)
        XCTAssertEqual(overdue("2027-03-10", "18:00"), false)
    }
}
