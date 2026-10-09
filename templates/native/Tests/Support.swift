import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit
import XCTest

/// A host with notes in memory, recording what plugins ask of it.
@MainActor
final class MockHost: NotesHost {
    var notes: [PluginNote]
    var folders: [PluginFolder]
    var created: [PluginNoteDraft] = []
    var opened: [String] = []
    var toasts: [String] = []

    init(notes: [PluginNote] = [], folders: [PluginFolder] = []) {
        self.notes = notes
        self.folders = folders
    }

    func show(_ message: String, icon: String) { toasts.append(message) }
    func cheer() {}
    func confirm(title: String, message: String?, actions: [String]) async -> Int? { 0 }
    func open(noteID: String) { opened.append(noteID) }
    func create(_ draft: PluginNoteDraft) -> String? {
        created.append(draft)
        let id = "new\(created.count)"
        notes.append(PluginNote(id: id, displayTitle: draft.title, title: draft.title, body: draft.body, folderID: draft.folderID,
                                tags: draft.tags, color: draft.color, pinned: draft.pinned, hidden: false, updatedAt: Date(),
                                createdAt: Date(), attachments: [], pluginData: draft.pluginData))
        return id
    }
    func updateNote(id: String, title: String?, body: NoteBody?) {}
    func setPluginData(noteID: String, pluginID: String, value: JSONValue?) {}
    func addAttachment(data: Data, name: String, contentType: String, kind: Attachment.Kind) async throws -> Attachment {
        Attachment(name: name, contentType: contentType, size: data.count, sha256: "", kind: kind)
    }
    func attachmentData(_ attachment: Attachment) async throws -> Data { Data() }
    let crossApp: any CrossAppClient = NoCrossApp()
    func isActive(_ pluginID: String) -> Bool { false }
}

@MainActor
final class NoCrossApp: CrossAppClient {
    func ensureScopes(_ scopes: [String]) async throws { throw CrossAppError.notSignedIn }
    func view(app: String, name: String) async throws -> JSONValue { throw CrossAppError.notSignedIn }
    func send(app: String, type: String, payload: JSONValue) async throws -> CrossAppCommand { throw CrossAppError.notSignedIn }
    func status(_ id: String) async throws -> CrossAppCommand { throw CrossAppError.notSignedIn }
    func cancel(_ id: String) async throws -> CancelOutcome { throw CrossAppError.notSignedIn }
}

func note(_ id: String, title: String = "", text: String = "", body: NoteBody? = nil, tags: [String] = [], created: Date = Date(),
          updated: Date? = nil, pluginData: [String: JSONValue] = [:], color: NoteColor? = nil) -> PluginNote {
    PluginNote(id: id, displayTitle: title.isEmpty ? nil : title, title: title, body: body ?? NoteBody(plainText: text), folderID: nil,
               tags: tags, color: color, pinned: false, hidden: false, updatedAt: updated ?? created, createdAt: created,
               attachments: [], pluginData: pluginData)
}

/// Renders a view at iPhone width in light and dark into /private/tmp/claude-501/shots/plugin-<name>-<light|dark>.png.
/// With no height, the view's own height is used. ImageRenderer, since a test bundle has no window scene to draw a
/// UIHostingController's window into. ImageRenderer leaves Liquid Glass (iOS 26+) and its contents blank, so files
/// are only written on earlier systems (run on the iPhone 15 Pro iOS 17 simulator, also 393pt wide); later ones
/// just check the view renders.
@MainActor
func snapshot<V: View>(_ view: V, name: String, height: CGFloat? = nil, background: Bool = true) throws {
    let width: CGFloat = 393
    let write: Bool
    if #available(iOS 26, *) { write = false } else { write = true }
    for scheme in [ColorScheme.light, .dark] {
        let root = ZStack(alignment: .top) {
            if background { NucleusBackground() }
            view.fixedSize(horizontal: false, vertical: height == nil)
        }
        .frame(width: width, height: height)
        .frame(minHeight: height == nil ? 1 : nil)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        let image = try XCTUnwrap(renderer.uiImage)
        guard write else { continue }
        let dir = URL(fileURLWithPath: "/private/tmp/claude-501/shots")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: dir.appendingPathComponent("plugin-\(name)-\(scheme == .dark ? "dark" : "light").png"))
    }
}

/// NucleusSheetPage's chrome without its ScrollView, which ImageRenderer leaves blank.
struct SheetShot<Content: View>: View {
    let title: String
    var confirm: String?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            NucleusBackground()
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.top, 72)
                .padding(.bottom, 32)
            HStack {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.glyph)
                    .frame(width: 40, height: 40).nucleusGlass(in: Circle())
                Spacer()
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Nucleus.primaryText)
                Spacer()
                if let confirm {
                    Text(confirm).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 16)
                        .frame(height: 40).background(Capsule().fill(Nucleus.primaryGradient))
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
            }
            .padding(16)
        }
    }
}
