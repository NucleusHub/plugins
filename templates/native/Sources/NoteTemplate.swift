import Foundation
import NotesPluginKit

/// A note to start from: a title and body that may hold `{{placeholders}}`, plus a color.
public struct NoteTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// SF Symbol for the card.
    public var icon: String
    public var title: String
    public var body: NoteBody
    public var color: NoteColor?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, icon: String = "doc.text.fill", title: String, body: NoteBody,
                color: NoteColor? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.title = title
        self.body = body
        self.color = color
        self.createdAt = createdAt
    }

    /// The one built in with this id.
    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    /// A template from a note: its title, text and color. Images, files and plugin cards are left out,
    /// since their attachments belong to the original note.
    public static func from(note: PluginNote, name: String, now: Date = Date()) -> NoteTemplate {
        let blocks = note.body.blocks
            .filter { !$0.type.isMedia || $0.type == .divider }
            .map { block -> Block in
                var copy = block
                copy.id = Block.makeID()
                return copy
            }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteTemplate(name: trimmed.isEmpty ? (note.displayTitle ?? "Template") : trimmed, icon: "square.on.square.fill",
                            title: note.title, body: NoteBody(blocks: blocks).normalized(), color: note.color, createdAt: now)
    }

    /// The draft for a new note, placeholders filled for `date`.
    public func draft(on date: Date = Date(), filler: PlaceholderFiller = PlaceholderFiller(), folderID: String? = nil) -> PluginNoteDraft {
        PluginNoteDraft(title: filler.fill(title, on: date), body: filler.fill(body, on: date), folderID: folderID, color: color)
    }
}

/// Replaces `{{date}}`, `{{time}}`, `{{weekday}}`, `{{week}}`, `{{month}}`, `{{year}}`, `{{tomorrow}}` and
/// `{{day:1}}`…`{{day:7}}` (the days of the current week) with values for the person's locale.
/// Unknown placeholders are left as they are.
public struct PlaceholderFiller: Sendable {
    public var locale: Locale
    public var calendar: Calendar

    public init(locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent, timeZone: TimeZone? = nil) {
        self.locale = locale
        var calendar = calendar
        calendar.locale = locale
        if let timeZone { calendar.timeZone = timeZone }
        self.calendar = calendar
    }

    public func value(for key: String, on date: Date) -> String? {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch key.lowercased() {
        case "date": style = style.year().month(.wide).day()
        case "time": style = style.hour().minute()
        case "weekday": style = style.weekday(.wide)
        case "month": style = style.month(.wide).year()
        case "year": style = style.year()
        case "week": return String(calendar.component(.weekOfYear, from: date))
        case "tomorrow":
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return next.formatted(style.weekday(.wide).month(.wide).day())
        default:
            let parts = key.split(separator: ":")
            guard parts.count == 2, parts[0].lowercased() == "day", let n = Int(parts[1]), (1...7).contains(n),
                  let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
                  let day = calendar.date(byAdding: .day, value: n - 1, to: start) else { return nil }
            return day.formatted(style.weekday(.wide).month(.abbreviated).day())
        }
        return date.formatted(style)
    }

    public func fill(_ text: String, on date: Date) -> String {
        guard text.contains("{{") else { return text }
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else {
                rest = rest[open.lowerBound...]
                break
            }
            let key = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            out += value(for: key, on: date) ?? String(rest[open.lowerBound..<close.upperBound])
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    public func fill(_ body: NoteBody, on date: Date) -> NoteBody {
        var body = body
        for b in body.blocks.indices {
            for r in body.blocks[b].runs.indices {
                body.blocks[b].runs[r].text = fill(body.blocks[b].runs[r].text, on: date)
            }
            body.blocks[b].id = Block.makeID()
        }
        return body
    }
}
