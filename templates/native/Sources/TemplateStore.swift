import Foundation
import Observation

/// The person's own templates, in a JSON file on this device (they don't sync).
@MainActor
@Observable
public final class TemplateStore {
    public static let shared = TemplateStore()

    public private(set) var templates: [NoteTemplate] = []
    private let fileURL: URL

    public init(fileURL: URL = TemplateStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([NoteTemplate].self, from: data) {
            templates = saved
        }
    }

    public nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Plugins/templates/user-templates.json")
    }

    /// Newest first.
    public func add(_ template: NoteTemplate) {
        templates.insert(template, at: 0)
        save()
    }

    public func delete(id: String) {
        templates.removeAll { $0.id == id }
        save()
    }

    public func removeAll() {
        templates = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(templates).write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Templates not saved: \(error)")
        }
    }
}
