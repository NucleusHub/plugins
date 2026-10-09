import Foundation
import NotesPluginKit

/// Recognized text per scanned page, kept in the note's plugin data as `{attachmentId: text}`.
enum ScanTexts {
    static func decode(_ value: JSONValue?) -> [String: String] {
        guard let object = value?.object else { return [:] }
        return object.compactMapValues { $0.string }
    }

    static func encode(_ texts: [String: String]) -> JSONValue? {
        texts.isEmpty ? nil : .object(texts.mapValues { .string($0) })
    }

    /// The texts of pages still in the body, in body order: what search should match.
    static func searchText(for note: PluginNote) -> String? {
        let texts = decode(note.pluginData[ScanPlugin.pluginID])
        let joined = note.body.attachmentIDs.compactMap { texts[$0] }.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// Only the pages the body still shows; nil when nothing changes.
    static func pruned(_ texts: [String: String], body: NoteBody) -> [String: String]? {
        let ids = Set(body.attachmentIDs)
        let kept = texts.filter { ids.contains($0.key) }
        return kept.count == texts.count ? nil : kept
    }

    /// Vision's lines as text: trimmed, blank lines dropped.
    static func clean(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Paragraph blocks of a page's text, to insert into the note.
    static func blocks(for text: String) -> [Block] {
        text.components(separatedBy: "\n").map { Block(text: $0) }
    }

    static func title(for date: Date, locale: Locale = .current) -> String {
        let stamp = date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
        return String(localized: "Scan \(stamp)")
    }

    /// A page's size scaled down so its long side is at most `maxSide`.
    static func fitted(_ size: CGSize, maxSide: CGFloat = 2560) -> CGSize {
        let long = max(size.width, size.height)
        guard long > maxSide, long > 0 else { return size }
        let scale = maxSide / long
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// Texts and attachments made before the note saved them, so the section can show them right away
/// (an insert action has no binding to the note's plugin data, and a new note may not exist yet).
@MainActor
final class PendingScans {
    static let shared = PendingScans()
    var texts: [String: String] = [:]
    var attachments: [String: Attachment] = [:]
}
