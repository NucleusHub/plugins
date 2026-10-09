import Foundation
import NotesPluginKit

/// Transcripts per recording, kept in the note's plugin data as `{attachmentId: transcript}`.
enum Transcripts {
    static func decode(_ value: JSONValue?) -> [String: String] {
        guard let object = value?.object else { return [:] }
        return object.compactMapValues { $0.string }
    }

    static func encode(_ transcripts: [String: String]) -> JSONValue? {
        transcripts.isEmpty ? nil : .object(transcripts.mapValues { .string($0) })
    }

    /// Transcripts of recordings still in the body, in body order.
    static func searchText(for note: PluginNote) -> String? {
        let transcripts = decode(note.pluginData[VoiceMemoPlugin.pluginID])
        let joined = note.body.attachmentIDs.compactMap { transcripts[$0] }.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// With `transcript` set for `id`, and recordings gone from the body dropped.
    static func setting(_ transcript: String, for id: String, in value: JSONValue?, body: NoteBody) -> JSONValue? {
        let ids = Set(body.attachmentIDs)
        var all = decode(value).filter { ids.contains($0.key) }
        all[id] = transcript
        return encode(all)
    }

    /// The locale to transcribe in: the device's when speech supports it, else its language's first match, else US English.
    static func locale(current: Locale, supported: Set<String>) -> Locale {
        let normalized = Set(supported.map { $0.replacingOccurrences(of: "_", with: "-") })
        let id = current.identifier(.bcp47)
        if normalized.contains(id) { return Locale(identifier: id) }
        if let language = current.language.languageCode?.identifier,
           let match = normalized.sorted().first(where: { $0.hasPrefix(language + "-") || $0 == language }) {
            return Locale(identifier: match)
        }
        return Locale(identifier: "en-US")
    }
}

enum AudioMath {
    static let maxDuration: TimeInterval = 30 * 60

    /// `m:ss`, or `h:mm:ss` from an hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// A meter reading in dBFS (−160…0) as 0…1, with the quiet end (below −50 dB) at 0.
    static func level(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let floor: Float = -50
        return min(max((decibels - floor) / -floor, 0), 1)
    }

    /// Peaks as bar heights 0…1, the loudest at 1; at least a sliver so silence still draws.
    static func normalizedBars(_ peaks: [Float], minimum: Float = 0.06) -> [Float] {
        let top = peaks.max() ?? 0
        guard top > 0 else { return peaks.map { _ in minimum } }
        return peaks.map { max($0 / top, minimum) }
    }

    /// The next playback speed: 1× → 1.5× → 2× → 1×.
    static func nextRate(after rate: Float) -> Float {
        switch rate {
        case ..<1.25: 1.5
        case ..<1.75: 2
        default: 1
        }
    }

    static func rateLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%.1f×", rate)
    }
}

/// Recordings and transcripts made before the note saved them (an insert action can't write the plugin data binding).
@MainActor
final class PendingMemos {
    static let shared = PendingMemos()
    var attachments: [String: Attachment] = [:]
    /// Transcripts of hidden notes live only here: plugin data isn't sealed in the vault.
    var transcripts: [String: String] = [:]
    var failed: Set<String> = []
}
