import Foundation
import NotesPluginKit
import SwiftUI
import UIKit
import XCTest

@MainActor
final class FakeHost: NotesHost {
    var notes: [PluginNote]
    var folders: [PluginFolder] = []
    var toasts: [String] = []
    var confirmAnswer: Int?
    var created: [PluginNoteDraft] = []
    var updates: [(id: String, title: String?, body: NoteBody?)] = []
    var pluginData: [String: [String: JSONValue?]] = [:]
    var stored: [String: Data] = [:]

    init(notes: [PluginNote] = []) { self.notes = notes }

    func show(_ message: String, icon: String) { toasts.append(message) }
    func cheer() {}
    func confirm(title: String, message: String?, actions: [String]) async -> Int? { confirmAnswer }
    func open(noteID: String) {}
    func create(_ draft: PluginNoteDraft) -> String? {
        created.append(draft)
        let id = "new\(created.count)"
        notes.append(note(id, title: draft.title, body: draft.body))
        return id
    }
    func updateNote(id: String, title: String?, body: NoteBody?) { updates.append((id, title, body)) }
    func setPluginData(noteID: String, pluginID: String, value: JSONValue?) { pluginData[noteID, default: [:]][pluginID] = value }
    func addAttachment(data: Data, name: String, contentType: String, kind: Attachment.Kind) async throws -> Attachment {
        let attachment = Attachment(name: name, contentType: contentType, size: data.count, sha256: "", kind: kind)
        stored[attachment.id] = data
        return attachment
    }
    func attachmentData(_ attachment: Attachment) async throws -> Data {
        guard let data = stored[attachment.id] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
    var crossApp: any CrossAppClient { FakeCrossApp() }
    func isActive(_ pluginID: String) -> Bool { false }
}

@MainActor
final class FakeCrossApp: CrossAppClient {
    func ensureScopes(_ scopes: [String]) async throws {}
    func view(app: String, name: String) async throws -> JSONValue { .null }
    func send(app: String, type: String, payload: JSONValue) async throws -> CrossAppCommand { throw CrossAppError.network }
    func status(_ id: String) async throws -> CrossAppCommand { throw CrossAppError.network }
    func cancel(_ id: String) async throws -> CancelOutcome { .cancelled }
}

func note(_ id: String, title: String, body: NoteBody = NoteBody(), hidden: Bool = false, updated: TimeInterval = 0,
          attachments: [Attachment] = [], pluginData: [String: JSONValue] = [:]) -> PluginNote {
    let display = title.isEmpty ? body.firstLine : title
    return PluginNote(id: id, displayTitle: display, title: title, body: body, folderID: nil, tags: [], color: nil, pinned: false,
                      hidden: hidden, updatedAt: Date().addingTimeInterval(updated),
                      createdAt: Date(timeIntervalSince1970: 1_700_000_000), attachments: attachments, pluginData: pluginData)
}

/// Renders a view at phone width in light and dark into the shots folder. Needs a window scene, so it
/// runs only in a test bundle hosted by an app (the package's own test run skips it).
@MainActor
func snapshot<V: View>(_ name: String, width: CGFloat = 393, height: CGFloat? = nil, @ViewBuilder _ view: () -> V) throws {
    let folder = URL(fileURLWithPath: "/private/tmp/claude-501/shots")
    guard FileManager.default.fileExists(atPath: folder.path),
          let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { throw XCTSkip("Needs a host app") }
    let content = view()
    for style in [UIUserInterfaceStyle.light, .dark] {
        let controller = UIHostingController(rootView: content.frame(width: width))
        controller.overrideUserInterfaceStyle = style
        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        let size = CGSize(width: width, height: height ?? max(fitted.height, 1))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.backgroundColor = style == .dark ? .black : .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        let suffix = style == .dark ? "dark" : "light"
        try image.pngData()?.write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
    }
}
