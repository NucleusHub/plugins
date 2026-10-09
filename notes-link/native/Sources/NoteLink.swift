import CryptoKit
import Foundation
import TodoPluginKit

/// A task's note, kept in `pluginData["notes-link"]`.
public struct NoteLink: Codable, Hashable, Sendable {
    public struct Pending: Codable, Hashable, Sendable {
        /// The `createNote` command.
        public var commandId: String

        public init(commandId: String) { self.commandId = commandId }
    }

    public var noteId: String
    public var title: String
    /// "tint:<NucleusTint>" or "#RRGGBB", as Notes publishes it.
    public var color: String?
    /// Sent with `createNote` and not seen in Notes' view yet.
    public var pending: Pending?
    /// Gone from Notes' view: hidden, locked, archived or deleted.
    public var missing: Bool?

    public init(noteId: String, title: String, color: String? = nil, pending: Pending? = nil, missing: Bool? = nil) {
        self.noteId = noteId
        self.title = title
        self.color = color
        self.pending = pending
        self.missing = missing
    }

    public init?(_ json: JSONValue?) {
        guard let json, let link = try? json.decode(NoteLink.self) else { return nil }
        self = link
    }

    public var json: JSONValue { (try? JSONValue(encoding: self)) ?? .null }

    /// The id Notes gives the note a `createNote` command makes: the first 24 hex of sha256(command id).
    public static func noteID(forCommand id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).lowercased()
    }

    /// The link after a look at Notes' view: fresh title and color, or marked missing.
    /// A note still being created isn't missing yet; it shows up once Notes syncs.
    public func refreshed(with notes: [String: SharedNote]) -> NoteLink {
        var new = self
        if let note = notes[noteId] {
            new.title = note.displayTitle
            new.color = note.color
            new.pending = nil
            new.missing = nil
        } else if pending == nil {
            new.missing = true
        }
        return new
    }

    /// The `createNote` payload for a task.
    public static func createPayload(title: String, text: String, taskID: String) -> JSONValue {
        [
            "title": .string(title),
            "text": .string(text),
            "link": ["app": "todo", "kind": "task", "id": .string(taskID), "title": .string(title)],
        ]
    }

    /// Where Notes opens the note.
    public var url: URL? { URL(string: "com.nucleushome.notes://note/\(noteId)") }
}

/// One note of Notes' published `notes` view.
public struct SharedNote: Decodable, Identifiable, Hashable, Sendable {
    public struct Checklist: Decodable, Hashable, Sendable {
        public var done: Int
        public var total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    public var id: String
    public var title: String
    public var snippet: String?
    public var color: String?
    public var folder: String?
    public var pinned: Bool
    public var checklist: Checklist?
    /// ISO 8601, so it sorts as text.
    public var updatedAt: String

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        snippet = try? c.decodeIfPresent(String.self, forKey: .snippet)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
        folder = try? c.decodeIfPresent(String.self, forKey: .folder)
        pinned = (try? c.decodeIfPresent(Bool.self, forKey: .pinned)) ?? false
        checklist = (try? c.decodeIfPresent(Checklist.self, forKey: .checklist)).flatMap { $0.total > 0 ? $0 : nil }
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case id, title, snippet, color, folder, pinned, checklist, updatedAt }

    public var displayTitle: String { title.isEmpty ? String(localized: "Untitled note") : title }

    /// Notes that don't parse are skipped; pinned first, then the most recently edited.
    public static func list(_ value: JSONValue) -> [SharedNote] {
        (value["notes"]?.array ?? [])
            .compactMap { try? $0.decode(SharedNote.self) }
            .sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updatedAt > b.updatedAt }
    }

    public static func byID(_ notes: [SharedNote]) -> [String: SharedNote] {
        Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A note color as Notes stores it.
public enum NoteColor: Hashable, Sendable {
    /// A NucleusTint name.
    case tint(String)
    case hex(UInt32)

    public init?(_ raw: String?) {
        guard let raw else { return nil }
        if raw.hasPrefix("tint:") {
            let name = String(raw.dropFirst(5))
            guard !name.isEmpty else { return nil }
            self = .tint(name)
        } else if raw.hasPrefix("#"), raw.count == 7, let value = UInt32(raw.dropFirst(), radix: 16) {
            self = .hex(value)
        } else {
            return nil
        }
    }
}
