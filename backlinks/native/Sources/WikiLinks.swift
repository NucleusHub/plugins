import Foundation
import NotesPluginKit

/// `[[Note title]]` typed in a body, turned into real links to notes.
enum WikiLinks {
    /// The `[[…]]` titles in a body, trimmed, first-seen order, each once (compared folded).
    static func titles(in body: NoteBody) -> [String] {
        var seen = Set<String>()
        var titles: [String] = []
        for block in body.blocks where convertible(block) {
            for match in matches(in: block) where seen.insert(NoteSearch.fold(match.title)).inserted {
                titles.append(match.title)
            }
        }
        return titles
    }

    /// Note ids for titles: an exact title wins over a case- and diacritic-insensitive one,
    /// and among equals the most recently edited note. Keyed by the folded title.
    static func resolve(_ titles: [String], in notes: [PluginNote]) -> [String: String] {
        let newestFirst = notes.sorted { $0.updatedAt > $1.updatedAt }
        var exact: [String: String] = [:]
        var folded: [String: String] = [:]
        for note in newestFirst {
            guard let title = note.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { continue }
            if exact[title] == nil { exact[title] = note.id }
            let key = NoteSearch.fold(title)
            if folded[key] == nil { folded[key] = note.id }
        }
        var out: [String: String] = [:]
        for title in titles {
            let key = NoteSearch.fold(title)
            if out[key] == nil, let id = exact[title] ?? folded[key] { out[key] = id }
        }
        return out
    }

    /// The body with every resolvable `[[Title]]` replaced by a link run reading `Title`; and how many were replaced.
    /// `ids` is keyed by the folded title, as `resolve` returns it.
    static func apply(_ body: NoteBody, ids: [String: String]) -> (body: NoteBody, converted: Int) {
        var out = body
        var converted = 0
        for i in out.blocks.indices where convertible(out.blocks[i]) {
            let (block, count) = convert(out.blocks[i], ids: ids)
            out.blocks[i] = block
            converted += count
        }
        return (out, converted)
    }

    // MARK: Matching

    struct Match {
        /// Character offsets in the block's text, brackets included.
        let range: Range<Int>
        let title: String
    }

    private static func convertible(_ block: Block) -> Bool { !block.type.isMedia && block.type != .code }

    /// `[[…]]` spans outside code and existing links.
    static func matches(in block: Block) -> [Match] {
        guard let chars = characters(of: block) else { return [] }
        var found: [Match] = []
        var i = 0
        while i + 1 < chars.count {
            guard chars[i].char == "[", chars[i + 1].char == "[" else { i += 1; continue }
            var j = i + 2
            while j < chars.count, !"[]\n".contains(chars[j].char) { j += 1 }
            let closes = j + 1 < chars.count && chars[j].char == "]" && chars[j + 1].char == "]"
            guard closes else { i += 1; continue }
            let span = i..<(j + 2)
            let title = String(chars[(i + 2)..<j].map(\.char)).trimmingCharacters(in: .whitespaces)
            let plain = span.allSatisfy { !block.runs[chars[$0].run].code && block.runs[chars[$0].run].link == nil }
            if !title.isEmpty, plain {
                found.append(Match(range: span, title: title))
                i = j + 2
            } else {
                i += 1
            }
        }
        return found
    }

    private static func convert(_ block: Block, ids: [String: String]) -> (Block, Int) {
        let resolved = matches(in: block).compactMap { m in ids[NoteSearch.fold(m.title)].map { (m, $0) } }
        guard !resolved.isEmpty, let chars = characters(of: block) else { return (block, 0) }
        var runs: [Run] = []
        func add(_ run: Run) {
            if let last = runs.last, last.hasSameMarks(as: run) { runs[runs.count - 1].text += run.text } else { runs.append(run) }
        }
        var k = 0
        for (match, id) in resolved {
            while k < match.range.lowerBound {
                var piece = block.runs[chars[k].run]
                piece.text = String(chars[k].char)
                add(piece)
                k += 1
            }
            // The link takes the marks of the title's first letter.
            var link = block.runs[chars[match.range.lowerBound + 2].run]
            link.text = match.title
            link.link = NoteLink.url(for: id)
            add(link)
            k = match.range.upperBound
        }
        while k < chars.count {
            var piece = block.runs[chars[k].run]
            piece.text = String(chars[k].char)
            add(piece)
            k += 1
        }
        var out = block
        out.runs = runs
        return (out, resolved.count)
    }

    /// Each character with the run it came from; nil when joining runs merged characters (rare combining marks).
    private static func characters(of block: Block) -> [(char: Character, run: Int)]? {
        var chars: [(char: Character, run: Int)] = []
        for (index, run) in block.runs.enumerated() {
            for c in run.text { chars.append((c, index)) }
        }
        return chars.count == block.text.count ? chars : nil
    }
}
