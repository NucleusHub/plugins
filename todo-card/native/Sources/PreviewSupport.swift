#if DEBUG
import Foundation
import NotesPluginKit
import NucleusUI
import SwiftUI

/// A Todo that answers from memory, for previews and tests.
@MainActor
final class FakeTodoClient: CrossAppClient {
    var views: [String: JSONValue]
    var sent: [CrossAppCommand] = []
    var statuses: [String: CrossAppCommand] = [:]
    var failViews: CrossAppError?
    var failSends: CrossAppError?
    private var counter = 0

    init(views: [String: JSONValue] = [:]) { self.views = views }

    func ensureScopes(_ scopes: [String]) async throws {}

    func view(app: String, name: String) async throws -> JSONValue {
        if let failViews { throw failViews }
        guard let value = views["\(app)/\(name)"] else { throw CrossAppError.http(404, nil) }
        return value
    }

    func send(app: String, type: String, payload: JSONValue) async throws -> CrossAppCommand {
        if let failSends { throw failSends }
        counter += 1
        let command = CrossAppCommand(id: "cmd\(counter)", from: "notes", to: app, type: type, payload: payload, status: .pending)
        sent.append(command)
        statuses[command.id] = command
        return command
    }

    func status(_ id: String) async throws -> CrossAppCommand {
        guard let command = statuses[id] else { throw CrossAppError.http(404, nil) }
        return command
    }

    func cancel(_ id: String) async throws -> CancelOutcome { .cancelled }
}

/// A Notes app with nothing in it but toasts, for previews and tests.
@MainActor
final class FakeNotesHost: NotesHost {
    var notes: [PluginNote] = []
    var folders: [PluginFolder] = []
    var toasts: [String] = []
    var pluginData: [String: [String: JSONValue]] = [:]
    let client: FakeTodoClient

    init(client: FakeTodoClient) { self.client = client }

    var crossApp: any CrossAppClient { client }
    func show(_ message: String, icon: String) { toasts.append(message) }
    func cheer() {}
    func confirm(title: String, message: String?, actions: [String]) async -> Int? { nil }
    func open(noteID: String) {}
    func create(_ draft: PluginNoteDraft) -> String? { nil }
    func updateNote(id: String, title: String?, body: NoteBody?) {}
    func setPluginData(noteID: String, pluginID: String, value: JSONValue?) { pluginData[noteID, default: [:]][pluginID] = value }
    func addAttachment(data: Data, name: String, contentType: String, kind: Attachment.Kind) async throws -> Attachment {
        throw CrossAppError.network
    }
    func attachmentData(_ attachment: Attachment) async throws -> Data { Data() }
    func isActive(_ pluginID: String) -> Bool { true }
}

enum TodoSamples {
    static let now = Date()

    static func day(_ offset: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Calendar.current.date(byAdding: .day, value: offset, to: now)!)
    }

    static var groceries: TodoList {
        TodoList(listId: "a1b2c3d4e5f6a1b2c3d4e5f6", name: "Groceries", icon: "cart.fill", tint: "emerald", tasks: [
            TodoTask(id: "t1", title: "Oat milk", due: day(0), priority: 0),
            TodoTask(id: "t2", title: "Sourdough from the corner bakery", priority: 2, flagged: true),
            TodoTask(id: "t3", title: "Basil and cherry tomatoes", due: day(1)),
            TodoTask(id: "t4", title: "Parmesan", due: day(-1), priority: 3),
            TodoTask(id: "t5", title: "Olive oil"),
            TodoTask(id: "t6", title: "Eggs", done: true, completedAt: Timestamp.string(now.addingTimeInterval(-3600))),
            TodoTask(id: "t7", title: "Coffee beans", done: true, completedAt: Timestamp.string(now.addingTimeInterval(-86_400))),
        ])
    }

    static var inbox: TodoList {
        TodoList(listId: nil, name: "Inbox", icon: "tray.fill", tint: "indigo", tasks: [
            TodoTask(id: "i1", title: "Call the landlord about the heating", due: day(0), time: "17:30"),
            TodoTask(id: "i2", title: "Return the library books"),
        ])
    }

    static var trip: TodoList {
        TodoList(listId: "f0e1d2c3b4a5f0e1d2c3b4a5", name: "Lisbon trip", icon: "airplane", tint: "sky", tasks: [
            TodoTask(id: "l1", title: "Book the tram tour", done: true, completedAt: Timestamp.string(now)),
            TodoTask(id: "l2", title: "Pack the adapter", done: true, completedAt: Timestamp.string(now)),
        ])
    }

    static func view(_ lists: [TodoList]) -> JSONValue {
        .object(["lists": .array(lists.map { list in
            .object(["id": list.listId.map(JSONValue.string) ?? .null, "name": .string(list.name), "icon": .string(list.icon),
                     "tint": .string(list.tint), "color": .null,
                     "tasks": .array(list.tasks.map { (try? JSONValue(encoding: $0)) ?? .null })])
        })])
    }

    /// A note with Groceries (one check on its way, one task being added) and a finished trip list.
    static var data: TodoCardData {
        var d = TodoCardData()
        d = TodoCardLogic.attach(groceries, to: d, now: now)
        d = TodoCardLogic.attach(trip, to: d, now: now)
        d.pending = [
            PendingOp(commandId: "c1", kind: .setDone, listId: groceries.listId, taskId: "t5", done: true, title: "Olive oil",
                      sentAt: Timestamp.string(now)),
            PendingOp(commandId: "c2", kind: .addTask, listId: groceries.listId, taskId: "n1", title: "Lemons",
                      sentAt: Timestamp.string(now)),
        ]
        return d
    }

    @MainActor
    static func host() -> FakeNotesHost {
        FakeNotesHost(client: FakeTodoClient(views: ["todo/lists": view([inbox, groceries, trip])]))
    }
}

/// The section as a note's editor would show it, on the app's background.
struct TodoCardPreview: View {
    @State var value: JSONValue?
    @State var body0 = NoteBody()
    let host: FakeNotesHost
    let scrolls: Bool
    let store: TodoCardStore

    init(data: TodoCardData = TodoSamples.data, host: FakeNotesHost = TodoSamples.host(), scrolls: Bool = true, offlineSince: Date? = nil) {
        _value = State(initialValue: data.json)
        self.host = host
        self.scrolls = scrolls
        store = TodoCardStore(host: host)
        if let offlineSince { store.pretendOffline(since: offlineSince) }
    }

    var body: some View {
        let section = TodoCardSection(value: $value, noteBody: $body0, store: store)
            .padding(16)
        Group {
            if scrolls { ScrollView { section } } else { section }
        }
        .background { NucleusBackground() }
    }
}

#Preview("Todo card") {
    TodoCardPreview()
}

#Preview("Offline") {
    TodoCardPreview(data: TodoCardLogic.attach(TodoSamples.inbox, to: TodoCardData(), now: Date()), offlineSince: Date().addingTimeInterval(-3 * 3600))
}

#Preview("Picker") {
    TodoListPicker(host: TodoSamples.host(), attached: ["inbox"], onPick: { _ in }, onCancel: {})
}
#endif
