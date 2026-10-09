import Foundation
import NotesPluginKit

/// A task as the card shows it: Todo's view with the commands still on their way laid over it.
public struct TaskRow: Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    public var due: String?
    public var time: String?
    public var priority: Int
    public var flagged: Bool
    /// A command for it is on its way to Todo.
    public var pending: Bool
    /// Added from the note and not in Todo yet; it can't be checked off until it is.
    public var isNew: Bool
    /// Done in Todo's view, so it sits under "Done" (a pending check stays where it was until Todo confirms).
    public var inDoneSection: Bool
}

/// The card's rules, pure so they can be tested without a server or a view.
public enum TodoCardLogic {
    public static let pluginID = "todo-card"
    static let app = "todo"
    static let view = "lists"

    /// Kept per list on the note so offline cards, chips and search have something to show.
    public static let maxOpen = 50
    public static let maxDone = 10
    /// An applied command the view still doesn't show is let go after this; the view then has the truth.
    public static let appliedGrace: TimeInterval = 10 * 60
    /// A command Todo hasn't picked up in this long stops showing as on its way.
    public static let pendingLimit: TimeInterval = 7 * 86_400

    // MARK: Attaching

    /// What the note keeps of a list: open tasks first (capped), then the latest done ones.
    public static func snapshot(_ list: TodoList, syncedAt: String?) -> AttachedList {
        let open = list.tasks.filter { !$0.done }
        let done = list.tasks.filter(\.done).sorted { ($0.completedAt ?? "") > ($1.completedAt ?? "") }
        return AttachedList(listId: list.listId, name: list.name, icon: list.icon, tint: list.tint,
                            tasks: Array(open.prefix(maxOpen)) + Array(done.prefix(maxDone)), open: open.count, syncedAt: syncedAt)
    }

    public static func attach(_ list: TodoList, to data: TodoCardData, now: Date) -> TodoCardData {
        var d = data
        let snap = snapshot(list, syncedAt: Timestamp.string(now))
        if let i = d.lists.firstIndex(where: { $0.id == snap.id }) { d.lists[i] = snap } else { d.lists.append(snap) }
        return d
    }

    /// Drops the list and whatever was still on its way for it.
    public static func remove(_ key: String, from data: TodoCardData) -> TodoCardData {
        var d = data
        guard let list = d.lists.first(where: { $0.id == key }) else { return d }
        let taskIDs = Set(list.tasks.map(\.id))
        d.lists.removeAll { $0.id == key }
        d.pending.removeAll { TodoList.key($0.listId) == key || taskIDs.contains($0.taskId) }
        return d
    }

    /// The body block that marks where the list was inserted.
    public static func embedBlock(for list: TodoList) -> Block {
        var ref: [String: JSONValue] = ["name": .string(list.name)]
        ref["listId"] = list.listId.map(JSONValue.string) ?? .null
        return Block(.embed, plugin: pluginID, ref: .object(ref))
    }

    /// List keys of this plugin's embed blocks, in body order.
    public static func embeddedKeys(in body: NoteBody) -> [(key: String, listId: String?, name: String)] {
        body.blocks.compactMap { block in
            guard block.type == .embed, block.plugin == pluginID, let ref = block.ref, ref.object != nil else { return nil }
            let id = ref["listId"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            return (TodoList.key(id), id, ref["name"]?.string ?? "")
        }
    }

    /// Lists embedded in the body but missing from the data (e.g. inserted on another device) get a card too.
    public static func adopt(_ body: NoteBody, into data: TodoCardData) -> TodoCardData {
        var d = data
        for embed in embeddedKeys(in: body) where !d.lists.contains(where: { $0.id == embed.key }) {
            let name = embed.name.isEmpty ? (embed.listId == nil ? "Inbox" : "Todo list") : embed.name
            d.lists.append(AttachedList(listId: embed.listId, name: name, icon: embed.listId == nil ? "tray" : "list.bullet"))
        }
        return d
    }

    public static func removingEmbeds(_ key: String, from body: NoteBody) -> NoteBody {
        var b = body
        b.blocks.removeAll { block in
            guard block.type == .embed, block.plugin == pluginID else { return false }
            return TodoList.key(block.ref?["listId"]?.string.flatMap { $0.isEmpty ? nil : $0 }) == key
        }
        return b
    }

    // MARK: Fresh views and commands

    /// Takes in a fresh `lists` view: updates the snapshots and lets go of commands the view now shows.
    public static func refreshed(_ data: TodoCardData, with lists: [TodoList], now: Date) -> TodoCardData {
        var d = data
        for i in d.lists.indices {
            let old = d.lists[i]
            guard let fresh = lists.first(where: { $0.id == old.id }) else {
                d.lists[i].missing = true
                continue
            }
            var snap = snapshot(fresh, syncedAt: old.syncedAt)
            // Stamped only when something changed, so an idle refresh doesn't edit the note.
            if snap.tasks != old.tasks || snap.open != old.open || old.syncedAt == nil { snap.syncedAt = Timestamp.string(now) }
            d.lists[i] = snap
        }
        let tasks = Dictionary(lists.flatMap(\.tasks).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        d.pending.removeAll { op in confirmed(op, tasks: tasks) || expired(op, now: now) }
        return d
    }

    static func confirmed(_ op: PendingOp, tasks: [String: TodoTask]) -> Bool {
        switch op.kind {
        case .setDone:
            guard let task = tasks[op.taskId] else { return op.status == .applied }
            return task.done == op.done
        case .addTask:
            return tasks[op.taskId] != nil
        }
    }

    static func expired(_ op: PendingOp, now: Date) -> Bool {
        switch op.status {
        case .rejected, .cancelled:
            return true
        case .applied:
            let since = Timestamp.date(op.settledAt) ?? Timestamp.date(op.sentAt) ?? .distantPast
            return now.timeIntervalSince(since) > appliedGrace
        case .pending, .delivered:
            return now.timeIntervalSince(Timestamp.date(op.sentAt) ?? .distantPast) > pendingLimit
        }
    }

    /// Keeps a sent command; a newer check of the same task replaces the older one.
    public static func record(_ op: PendingOp, in data: TodoCardData) -> TodoCardData {
        var d = data
        if op.kind == .setDone { d.pending.removeAll { $0.kind == .setDone && $0.taskId == op.taskId } }
        d.pending.append(op)
        return d
    }

    /// Takes in where a command is. A rejected one is dropped (the row snaps back) and returned for a message.
    public static func settled(_ command: CrossAppCommand, in data: TodoCardData, now: Date) -> (data: TodoCardData, rejected: PendingOp?) {
        var d = data
        guard let i = d.pending.firstIndex(where: { $0.commandId == command.id }) else { return (d, nil) }
        var op = d.pending[i]
        guard op.status != command.status else { return (d, nil) }
        op.status = command.status
        if command.status.isSettled { op.settledAt = Timestamp.string(now) }
        if op.kind == .addTask, let id = command.result?["taskId"]?.string, !id.isEmpty { op.taskId = id }
        switch command.status {
        case .rejected:
            d.pending.remove(at: i)
            return (d, op)
        case .cancelled:
            d.pending.remove(at: i)
        default:
            d.pending[i] = op
        }
        return (d, nil)
    }

    /// Commands still to be asked about.
    public static func unsettled(_ data: TodoCardData) -> [PendingOp] { data.pending.filter { !$0.status.isSettled } }

    /// Applied, but the view hasn't caught up: worth a fresh look.
    public static func awaitingView(_ data: TodoCardData) -> Bool { data.pending.contains { $0.status == .applied } }

    /// Todo's task id for an `addTask` command: the first 24 hex of the command id's SHA-256.
    public static func taskID(forCommand id: String) -> String { RecordID.derived(from: id) }

    // MARK: Showing

    public static func rows(_ list: AttachedList, pending: [PendingOp]) -> [TaskRow] {
        var rows = list.tasks.map {
            TaskRow(id: $0.id, title: $0.title, done: $0.done, due: $0.due, time: $0.time, priority: $0.priority,
                    flagged: $0.flagged, pending: false, isNew: false, inDoneSection: $0.done)
        }
        var added: [TaskRow] = []
        for op in pending.sorted(by: { $0.sentAt < $1.sentAt }) {
            switch op.kind {
            case .setDone:
                guard let i = rows.firstIndex(where: { $0.id == op.taskId }), let done = op.done else { continue }
                rows[i].done = done
                rows[i].pending = true
            case .addTask:
                guard TodoList.key(op.listId) == list.id, !rows.contains(where: { $0.id == op.taskId }) else { continue }
                added.append(TaskRow(id: op.taskId, title: op.title, done: false, priority: 0, flagged: false,
                                     pending: true, isNew: true, inDoneSection: false))
            }
        }
        return added + rows
    }

    /// Open tasks, counting those past the snapshot's cap.
    public static func openCount(_ list: AttachedList, rows: [TaskRow]) -> Int {
        let overflow = max(0, list.open - list.tasks.filter { !$0.done }.count)
        return rows.filter { !$0.done }.count + overflow
    }

    /// Done out of all tasks the card knows about.
    public static func progress(_ list: AttachedList, rows: [TaskRow]) -> (done: Int, total: Int) {
        let open = openCount(list, rows: rows)
        let done = rows.filter(\.done).count
        return (done, done + open)
    }

    public static func chip(_ data: TodoCardData) -> NoteChip? {
        guard let first = data.lists.first else { return nil }
        let left = data.lists.reduce(0) { $0 + openCount($1, rows: rows($1, pending: data.pending)) }
        let name = data.lists.count > 1 ? "\(first.name) +\(data.lists.count - 1)" : first.name
        let count = left == 0 ? String(localized: "All done") : String(localized: "\(left) left")
        let broken = data.lists.allSatisfy { $0.missing == true }
        return NoteChip(icon: broken ? "exclamationmark.triangle" : "checklist", text: "\(name) · \(count)")
    }

    /// Open tasks as Markdown checkboxes, under the list's name when there are several.
    public static func shareText(_ data: TodoCardData) -> String? {
        let groups = data.lists.map { list in
            (list.name, rows(list, pending: data.pending).filter { !$0.done }.map { "- [ ] \($0.title)" })
        }.filter { !$0.1.isEmpty }
        guard !groups.isEmpty else { return nil }
        if groups.count == 1 { return groups[0].1.joined(separator: "\n") }
        return groups.map { ([$0.0 + ":"] + $0.1).joined(separator: "\n") }.joined(separator: "\n\n")
    }

    public static func searchText(_ data: TodoCardData) -> String? {
        let words = data.lists.flatMap { [$0.name] + $0.tasks.map(\.title) } + data.pending.filter { $0.kind == .addTask }.map(\.title)
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// `com.nucleushome.todo://list/<id>`, or `…/list/inbox`.
    public static func url(listId: String?) -> URL {
        let id = listId?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "inbox"
        return URL(string: "com.nucleushome.todo://list/\(id)")!
    }

    /// "Today", "Tomorrow", "Mon" or "Oct 12" (with the time when there is one), and whether it's past.
    public static func dueLabel(due: String?, time: String?, now: Date, calendar: Calendar = .current) -> (text: String, overdue: Bool)? {
        guard let due, let day = dayFormatter(calendar).date(from: due) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0
        let text: String
        switch days {
        case 0: text = String(localized: "Today")
        case 1: text = String(localized: "Tomorrow")
        case -1: text = String(localized: "Yesterday")
        case 2..<7: text = day.formatted(.dateTime.weekday(.abbreviated).locale(calendar.locale ?? .current))
        default:
            let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            text = sameYear ? day.formatted(.dateTime.month(.abbreviated).day().locale(calendar.locale ?? .current))
                : day.formatted(.dateTime.month(.abbreviated).day().year().locale(calendar.locale ?? .current))
        }
        var overdue = days < 0
        if days == 0, let time, let at = timeFormatter(calendar).date(from: "\(due) \(time)") { overdue = at < now }
        return (time.map { "\(text) \($0)" } ?? text, overdue)
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static func timeFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = dayFormatter(calendar)
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }
}
