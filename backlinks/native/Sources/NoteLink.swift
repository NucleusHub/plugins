import Foundation

/// The URL of a note: a plain link, so it still opens the note when the plugin is off.
enum NoteLink {
    static let prefix = "com.nucleushome.notes://note/"

    static func url(for noteID: String) -> String { prefix + noteID }

    /// The note id a link points at, nil for any other link.
    static func noteID(in link: String?) -> String? {
        guard let link, link.lowercased().hasPrefix(prefix) else { return nil }
        let rest = link.dropFirst(prefix.count)
        let id = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return id.isEmpty ? nil : String(id)
    }
}
