#if DEBUG
import Foundation
import NotesPluginKit
import NucleusUI
import SwiftUI

/// A Watchlist that answers from memory, for previews and tests.
@MainActor
final class FakeWatchlistClient: CrossAppClient {
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
    let client: FakeWatchlistClient

    init(client: FakeWatchlistClient) { self.client = client }

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

enum WatchSamples {
    static let library: [LibraryTitle] = [
        LibraryTitle(id: "w1", title: "Severance", type: "show", status: "watching", seasons: [
            .init(number: 1, episodeCount: 9, watched: 9), .init(number: 2, episodeCount: 10, watched: 5),
        ]),
        LibraryTitle(id: "w2", title: "Past Lives", type: "movie", status: "planned"),
        LibraryTitle(id: "w3", title: "The Bear", type: "show", status: "completed", seasons: [
            .init(number: 1, episodeCount: 8, watched: 8), .init(number: 2, episodeCount: 10, watched: 10),
        ]),
        LibraryTitle(id: "w4", title: "Dune: Part Two", type: "movie", status: "watching"),
        LibraryTitle(id: "w5", title: "Shogun", type: "show", status: "planned", seasons: [.init(number: 1, episodeCount: 10)]),
    ]

    static func view(_ items: [LibraryTitle]) -> JSONValue {
        .object(["items": .array(items.map { item in
            .object(["id": .string(item.id), "title": .string(item.title), "type": .string(item.type), "tmdbId": 1,
                     "poster": item.poster.map(JSONValue.string) ?? .null, "status": item.status.map(JSONValue.string) ?? .null,
                     "seasons": .array(item.seasons.map { ["number": .number(Double($0.number)), "name": .string($0.name),
                                                           "episodeCount": .number(Double($0.episodeCount)), "watched": .number(Double($0.watched))] })])
        })])
    }

    /// Severance's second season, a planned movie, and a title deleted from Watchlist.
    static var cards: [WatchCard] {
        var gone = WatchCard(itemId: "gone", title: "Arcane", type: "show")
        gone.broken = true
        return [WatchCard(library[0], season: 2), WatchCard(library[1]), WatchCard(library[2]), gone]
    }

    @MainActor
    static func host() -> FakeNotesHost {
        FakeNotesHost(client: FakeWatchlistClient(views: ["watchlist/library": view(library)]))
    }
}

/// The section as a note's editor would show it, on the app's background.
struct WatchlistCardPreview: View {
    @State var value: JSONValue?
    @State var body0 = NoteBody()
    let scrolls: Bool
    let store: WatchlistCardStore

    init(cards: [WatchCard] = WatchSamples.cards, host: FakeNotesHost = WatchSamples.host(), scrolls: Bool = true, offlineSince: Date? = nil) {
        _value = State(initialValue: WatchCardLogic.json(cards))
        self.scrolls = scrolls
        store = WatchlistCardStore(host: host)
        if let offlineSince { store.pretendOffline(since: offlineSince) }
    }

    var body: some View {
        let section = WatchlistCardSection(value: $value, noteBody: $body0, store: store)
            .padding(16)
        Group {
            if scrolls { ScrollView { section } } else { section }
        }
        .background { NucleusBackground() }
    }
}

#Preview("Watchlist card") {
    WatchlistCardPreview()
}

#Preview("Picker") {
    WatchlistPicker(host: WatchSamples.host(), attached: ["w1"], onPick: { _ in }, onCancel: {})
}
#endif
