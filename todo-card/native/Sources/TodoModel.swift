import Foundation
import NotesPluginKit

/// One task of Todo's published `lists` view.
public struct TodoTask: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var done: Bool
    /// `yyyy-MM-dd`.
    public var due: String?
    /// `HH:mm`.
    public var time: String?
    /// 0 (none) to 3 (high).
    public var priority: Int
    public var flagged: Bool
    public var completedAt: String?

    public init(id: String, title: String, done: Bool = false, due: String? = nil, time: String? = nil, priority: Int = 0,
                flagged: Bool = false, completedAt: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.due = due
        self.time = time
        self.priority = priority
        self.flagged = flagged
        self.completedAt = completedAt
    }

    // Lenient: a field Todo adds, drops or nulls later shouldn't hide the task.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
        due = (try? c.decodeIfPresent(String.self, forKey: .due)) ?? nil
        time = (try? c.decodeIfPresent(String.self, forKey: .time)) ?? nil
        priority = min(max((try? c.decodeIfPresent(Int.self, forKey: .priority)) ?? 0, 0), 3)
        flagged = (try? c.decodeIfPresent(Bool.self, forKey: .flagged)) ?? false
        completedAt = (try? c.decodeIfPresent(String.self, forKey: .completedAt)) ?? nil
    }

    private enum CodingKeys: String, CodingKey { case id, title, done, due, time, priority, flagged, completedAt }
}

/// One list of Todo's `lists` view; a nil id is the Inbox.
public struct TodoList: Hashable, Sendable, Identifiable {
    public var listId: String?
    public var name: String
    /// An SF Symbol.
    public var icon: String
    /// A NucleusTint name.
    public var tint: String
    public var tasks: [TodoTask]

    public var id: String { TodoList.key(listId) }
    public var openCount: Int { tasks.filter { !$0.done }.count }

    public init(listId: String?, name: String, icon: String = "list.bullet", tint: String = "indigo", tasks: [TodoTask] = []) {
        self.listId = listId
        self.name = name
        self.icon = icon
        self.tint = tint
        self.tasks = tasks
    }

    /// Lists and tasks that don't parse are skipped rather than failing the whole view.
    public static func lists(_ value: JSONValue) -> [TodoList] {
        (value["lists"]?.array ?? []).compactMap { list -> TodoList? in
            guard list.object != nil else { return nil }
            let id = list["id"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            let name = list["name"]?.string ?? ""
            return TodoList(
                listId: id,
                name: name.isEmpty ? (id == nil ? "Inbox" : "Untitled") : name,
                icon: list["icon"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? (id == nil ? "tray" : "list.bullet"),
                tint: list["tint"]?.string ?? "indigo",
                tasks: (list["tasks"]?.array ?? []).compactMap { try? $0.decode(TodoTask.self) }
            )
        }
    }

    /// A list's identity in the plugin's data: its id, or "inbox".
    public static func key(_ listId: String?) -> String { listId ?? "inbox" }
}

/// A list attached to a note, with the tasks as last seen so the card, chip and search work offline.
public struct AttachedList: Codable, Hashable, Sendable, Identifiable {
    /// nil is the Inbox.
    public var listId: String?
    public var name: String
    public var icon: String
    public var tint: String
    /// Open tasks first, capped (see `TodoCardLogic.maxOpen`).
    public var tasks: [TodoTask]
    /// Open tasks in Todo, including any past the cap.
    public var open: Int
    /// When the tasks last changed.
    public var syncedAt: String?
    /// The list isn't in Todo's view any more (deleted).
    public var missing: Bool?

    public var id: String { TodoList.key(listId) }

    public init(listId: String?, name: String, icon: String = "list.bullet", tint: String = "indigo", tasks: [TodoTask] = [],
                open: Int = 0, syncedAt: String? = nil, missing: Bool? = nil) {
        self.listId = listId
        self.name = name
        self.icon = icon
        self.tint = tint
        self.tasks = tasks
        self.open = open
        self.syncedAt = syncedAt
        self.missing = missing
    }
}

/// A command sent to Todo that its view doesn't show yet.
public struct PendingOp: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case setDone, addTask }

    public var commandId: String
    public var kind: Kind
    /// The list the task shows in (for `addTask`, where it's added).
    public var listId: String?
    /// For `addTask`, derived from the command id the way Todo derives it.
    public var taskId: String
    /// `setDone` only.
    public var done: Bool?
    /// The task's title, for the optimistic row and messages.
    public var title: String
    public var status: CrossAppCommand.Status
    public var sentAt: String
    public var settledAt: String?

    public var id: String { commandId }

    public init(commandId: String, kind: Kind, listId: String?, taskId: String, done: Bool? = nil, title: String,
                status: CrossAppCommand.Status = .pending, sentAt: String, settledAt: String? = nil) {
        self.commandId = commandId
        self.kind = kind
        self.listId = listId
        self.taskId = taskId
        self.done = done
        self.title = title
        self.status = status
        self.sentAt = sentAt
        self.settledAt = settledAt
    }
}

/// What the plugin keeps on a note, in `pluginData["todo-card"]`.
public struct TodoCardData: Codable, Hashable, Sendable {
    public var lists: [AttachedList]
    public var pending: [PendingOp]

    public init(lists: [AttachedList] = [], pending: [PendingOp] = []) {
        self.lists = lists
        self.pending = pending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lists = (try? c.decodeIfPresent([AttachedList].self, forKey: .lists)) ?? []
        pending = (try? c.decodeIfPresent([PendingOp].self, forKey: .pending)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case lists, pending }

    public init(_ json: JSONValue?) {
        self = json.flatMap { try? $0.decode(TodoCardData.self) } ?? TodoCardData()
    }

    /// nil when there's nothing to keep, so a note without lists carries no data.
    public var json: JSONValue? {
        guard !lists.isEmpty || !pending.isEmpty else { return nil }
        return try? JSONValue(encoding: self)
    }
}
