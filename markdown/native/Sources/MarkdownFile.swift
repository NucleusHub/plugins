import Foundation
import NotesPluginKit

/// Notes to Markdown files and back.
public enum MarkdownFile {
    public static let maxNameLength = 80

    /// A file name for a note: characters Files and other systems reject removed, whitespace collapsed,
    /// cut to a sane length, `.md` added.
    public static func fileName(for title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|#%{}^~[]`").union(.controlCharacters).union(.newlines)
        var name = String(String.UnicodeScalarView(title.unicodeScalars.map { banned.contains($0) ? " " : $0 }))
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Leading dots hide a file; trailing dots and spaces trip Windows.
        name = String(name.drop { $0 == "." || $0 == " " })
        if name.count > maxNameLength { name = String(name.prefix(maxNameLength)) }
        while let last = name.last, last == "." || last == " " { name.removeLast() }
        return (name.isEmpty ? "Untitled note" : name) + ".md"
    }

    /// The note as Markdown: its title as a top heading, then the body. Attachments become
    /// `![](attachment:<id>)` references, since their bytes aren't in the file.
    public static func export(title: String, body: NoteBody) -> String {
        let text = body.markdown()
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else { return text + "\n" }
        return "# \(heading)\n\n\(text)" + (text.isEmpty ? "" : "\n")
    }

    /// Text from a file's bytes: UTF-8 (with or without a BOM), UTF-16 with a BOM, else Windows Latin 1.
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    }

    /// A note from a file. A first `# Heading` (or a front-matter `title:`) becomes the title, else the file name;
    /// `.txt` files keep their lines as plain paragraphs.
    public static func draft(text: String, fileName: String) -> PluginNoteDraft {
        let ext = (fileName as NSString).pathExtension.lowercased()
        var name = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = fileName }
        var source = text.replacingOccurrences(of: "\r\n", with: "\n")
        var title: String?
        if ext != "txt", let (front, rest) = splitFrontMatter(source) {
            source = rest
            title = front["title"]
        }
        if ext == "txt" {
            let lines = source.components(separatedBy: "\n")
            let start = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? lines.count
            return PluginNoteDraft(title: name, body: NoteBody(plainText: lines[start...].joined(separator: "\n").trimmingCharacters(in: .newlines)))
        }
        var body = NoteBody(markdown: source)
        if title == nil, let first = body.blocks.first, first.type == .heading1 {
            title = first.text.trimmingCharacters(in: .whitespaces)
            body.blocks.removeFirst()
        }
        return PluginNoteDraft(title: title ?? name, body: body)
    }

    /// The file's content as blocks to put into a note, headings and all (front matter left out).
    public static func blocks(text: String, fileName: String) -> [Block] {
        let source = text.replacingOccurrences(of: "\r\n", with: "\n")
        if (fileName as NSString).pathExtension.lowercased() == "txt" {
            return NoteBody(plainText: source.trimmingCharacters(in: .newlines)).blocks
        }
        return NoteBody(markdown: splitFrontMatter(source)?.1 ?? source).blocks
    }

    /// YAML front matter's simple `key: value` lines and the text after it.
    static func splitFrontMatter(_ text: String) -> ([String: String], String)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q { value = String(value.dropFirst().dropLast()) }
            if !key.isEmpty, !value.isEmpty { fields[key] = value }
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }
}
