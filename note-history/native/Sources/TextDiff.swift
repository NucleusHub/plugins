import Foundation
import NotesPluginKit

/// A plain-text line diff, enough to see what a version added or removed.
enum TextDiff {
    enum Kind: Hashable, Sendable { case same, added, removed }

    struct Line: Hashable, Sendable {
        let kind: Kind
        let text: String
    }

    /// Lines from `old` to `new` by longest common subsequence; removals come before additions at a change.
    static func lines(from old: [String], to new: [String]) -> [Line] {
        // Trim the shared start and end so the table only covers what changed.
        var start = 0
        while start < old.count, start < new.count, old[start] == new[start] { start += 1 }
        var oldEnd = old.count, newEnd = new.count
        while oldEnd > start, newEnd > start, old[oldEnd - 1] == new[newEnd - 1] { oldEnd -= 1; newEnd -= 1 }
        let a = Array(old[start..<oldEnd]), b = Array(new[start..<newEnd])

        var middle: [Line] = []
        if a.count * b.count > 4_000_000 {
            // Too big to compare line by line on a phone: show it as replaced.
            middle = a.map { Line(kind: .removed, text: $0) } + b.map { Line(kind: .added, text: $0) }
        } else {
            var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
            var i = 0, j = 0
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, a[i] == b[j] {
                    middle.append(Line(kind: .same, text: a[i])); i += 1; j += 1
                } else if j == b.count || (i < a.count && table[i + 1][j] >= table[i][j + 1]) {
                    middle.append(Line(kind: .removed, text: a[i])); i += 1
                } else {
                    middle.append(Line(kind: .added, text: b[j])); j += 1
                }
            }
        }
        return old[..<start].map { Line(kind: .same, text: $0) } + middle + old[oldEnd...].map { Line(kind: .same, text: $0) }
    }

    /// A note as lines of text: the title, then each block with a marker for its kind.
    static func text(title: String, body: NoteBody, attachments: [Attachment] = []) -> [String] {
        var lines: [String] = []
        if !title.isEmpty { lines.append(title) }
        let numbers = BodyNumbering.numbers(for: body.blocks)
        for (index, block) in body.blocks.enumerated() {
            let pad = String(repeating: "  ", count: block.indent)
            switch block.type {
            case .heading1: lines.append("# " + block.text)
            case .heading2: lines.append("## " + block.text)
            case .heading3: lines.append("### " + block.text)
            case .bullet: lines.append(pad + "• " + block.text)
            case .numbered: lines.append(pad + "\(numbers[index] ?? 1). " + block.text)
            case .check: lines.append(pad + (block.checked ? "☑ " : "☐ ") + block.text)
            case .quote: lines.append("> " + block.text)
            case .divider: lines.append("———")
            case .image: lines.append("[" + String(localized: "Image") + "]")
            case .file:
                let name = attachments.first { $0.id == block.attachment }?.name
                lines.append("[" + (name ?? String(localized: "File")) + "]")
            case .embed: continue
            case .paragraph, .code: lines.append(block.text)
            }
        }
        return lines
    }
}

/// The number a `numbered` block shows: counting up through neighbors at its indent.
enum BodyNumbering {
    static func numbers(for blocks: [Block]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        var counters: [Int] = []
        for (index, block) in blocks.enumerated() {
            guard block.type.isList else { counters = []; continue }
            // A shallower item ends the deeper lists under it.
            if counters.count > block.indent + 1 { counters.removeLast(counters.count - block.indent - 1) }
            while counters.count < block.indent + 1 { counters.append(0) }
            if block.type == .numbered {
                counters[block.indent] += 1
                out[index] = counters[block.indent]
            } else {
                counters[block.indent] = 0
            }
        }
        return out
    }
}
