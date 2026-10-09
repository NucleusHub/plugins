import Foundation
import NotesPluginKit

/// One saved state of a note.
struct NoteVersion: Codable, Hashable, Sendable, Identifiable {
    var savedAt: Date
    var title: String
    var body: NoteBody

    /// The file name stem: milliseconds since 1970, so names sort by age.
    var id: String { String(Int64((savedAt.timeIntervalSince1970 * 1000).rounded())) }

    var wordCount: Int { NoteBody(plainText: title).wordCount + body.wordCount }
}

/// Versions on disk: `<root>/<noteId>/<millis>.json`, at most `maxVersions` per note.
final class HistoryStore: @unchecked Sendable {
    static let shared = HistoryStore(root: URL.applicationSupportDirectory.appending(path: "NoteHistory", directoryHint: .isDirectory))
    static let maxVersions = 50

    let root: URL
    private let files = FileManager.default
    private let lock = NSLock()

    init(root: URL) {
        self.root = root
    }

    /// Newest first.
    func versions(of noteID: String) -> [NoteVersion] {
        lock.withLock { versionFiles(of: noteID).reversed().compactMap(read) }
    }

    func latest(of noteID: String) -> NoteVersion? {
        lock.withLock { versionFiles(of: noteID).last.flatMap(read) }
    }

    func save(_ version: NoteVersion, noteID: String) {
        guard let folder = folder(for: noteID) else { return }
        lock.withLock {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            guard let data = try? encoder.encode(version) else { return }
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appending(path: "\(version.id).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            for old in versionFiles(of: noteID).dropLast(Self.maxVersions) { try? files.removeItem(at: old) }
        }
    }

    func hasHistory(_ noteID: String) -> Bool {
        guard let folder = folder(for: noteID) else { return false }
        return files.fileExists(atPath: folder.path)
    }

    func delete(_ noteID: String) {
        guard let folder = folder(for: noteID) else { return }
        lock.withLock { try? files.removeItem(at: folder) }
    }

    /// Note ids that have versions.
    func noteIDs() -> [String] {
        (try? files.contentsOfDirectory(atPath: root.path))?.filter { !$0.hasPrefix(".") } ?? []
    }

    /// Removes the history of every note not in `ids`.
    func prune(keeping ids: Set<String>) {
        for id in noteIDs() where !ids.contains(id) {
            lock.withLock { try? files.removeItem(at: root.appending(path: id, directoryHint: .isDirectory)) }
        }
    }

    func clearAll() {
        lock.withLock { try? files.removeItem(at: root) }
    }

    /// Bytes on disk and how many notes they belong to.
    func usage() -> (bytes: Int, notes: Int) {
        let ids = noteIDs()
        var bytes = 0
        if let walker = files.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker {
                bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return (bytes, ids.count)
    }

    // MARK: Files

    private func folder(for noteID: String) -> URL? {
        // Ids become folder names; anything that could escape the root is refused.
        guard !noteID.isEmpty, noteID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return root.appending(path: noteID, directoryHint: .isDirectory)
    }

    /// Oldest first.
    private func versionFiles(of noteID: String) -> [URL] {
        guard let folder = folder(for: noteID),
              let names = try? files.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { name in Int64(name.dropLast(5)).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .map { folder.appending(path: $0.1) }
    }

    private func read(_ url: URL) -> NoteVersion? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode(NoteVersion.self, from: $0) }
    }
}
