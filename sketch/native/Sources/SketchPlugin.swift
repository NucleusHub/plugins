import NotesPluginKit
import NucleusPlugins
import NucleusUI
import PencilKit
import SwiftUI

/// Sketch: a PencilKit drawing in a note as an image, with the drawing kept so it can be edited again.
public struct SketchPlugin: Plugin {
    public let manifest: PluginManifest
    static let pluginID = "sketch"

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: Self.pluginID, name: "Sketch", version: "1.0.0", target: ["notes"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .insertActions, id: "sketch", SketchInsertAction() as any InsertAction)
        registrar.contribute(to: .noteSections, id: "sketches", SketchesNoteSection() as any NoteSection)
    }
}

/// What a finished sketch becomes: the PNG and, outside the vault, the drawing next to it.
enum SketchStore {
    @MainActor
    static func save(_ drawing: PKDrawing, paper: Paper, hidden: Bool, host: any NotesHost) async throws -> (png: Data, link: SketchLink)? {
        guard let png = SketchExporter.png(drawing, paper: paper) else { return nil }
        // The companion isn't in any block, so the app wouldn't seal it with a vault note: hidden notes keep only the image.
        var companion: Attachment?
        if !hidden {
            companion = try await host.addAttachment(data: drawing.dataRepresentation(), name: "Sketch.drawing",
                                                     contentType: "application/x-pkdrawing", kind: .file)
        }
        return (png, SketchLink(drawing: companion, paper: paper))
    }
}

struct SketchInsertAction: InsertAction {
    var title: LocalizedStringResource { "Sketch" }
    var icon: String { "pencil.tip.crop.circle" }

    @MainActor
    func sheet(_ context: InsertContext) -> AnyView? {
        AnyView(SketchSheet(onDone: { drawing, paper in await insert(drawing, paper, context) }, onCancel: context.dismiss))
    }

    @MainActor
    func insert(_ drawing: PKDrawing, _ paper: Paper, _ context: InsertContext) async {
        let host = context.host
        do {
            guard let (png, link) = try await SketchStore.save(drawing, paper: paper, hidden: context.note.hidden, host: host) else {
                return context.dismiss()
            }
            let image = try await context.insertAttachment(data: png, name: "Sketch.png", contentType: "image/png", kind: .drawing)
            PendingSketches.shared.images[image.id] = image
            PendingSketches.shared.links[image.id] = link
            let saved = host.notes.first { $0.id == context.note.id } ?? context.note
            var all = SketchLink.decodeAll(saved.pluginData[SketchPlugin.pluginID])
            all[image.id] = link
            host.setPluginData(noteID: context.note.id, pluginID: SketchPlugin.pluginID, value: SketchLink.encodeAll(all))
        } catch {
            host.show(String(localized: "Couldn't add the sketch. Try again."), icon: "exclamationmark.triangle.fill")
        }
        context.dismiss()
    }
}

struct SketchesNoteSection: NoteSection {
    @MainActor
    func view(_ context: NoteSectionContext) -> AnyView {
        AnyView(SketchesSection(note: context.note, host: context.host, noteBody: context.body,
                                value: context.pluginData(for: SketchPlugin.pluginID)))
    }
}

/// "Sketches": each sketch in the note with an Edit button that reopens the canvas.
struct SketchesSection: View {
    let note: PluginNote
    let host: any NotesHost
    @Binding var noteBody: NoteBody
    @Binding var value: JSONValue?
    @State private var editing: Editing?

    struct Editing: Identifiable {
        let imageID: String
        let drawing: PKDrawing
        let paper: Paper
        var id: String { imageID }
    }

    private var sketches: [(image: Attachment, link: SketchLink?)] {
        let links = SketchLink.decodeAll(value).merging(PendingSketches.shared.links) { saved, _ in saved }
        return noteBody.blocks.compactMap { block in
            guard block.type == .image, let id = block.attachment,
                  let image = note.attachments.first(where: { $0.id == id }) ?? PendingSketches.shared.images[id],
                  image.kind == .drawing || links[id] != nil else { return nil }
            return (image, links[id])
        }
    }

    var body: some View {
        let sketches = self.sketches
        Group {
            if !sketches.isEmpty {
                NucleusSection("Sketches") {
                    ForEach(Array(sketches.enumerated()), id: \.element.image.id) { index, sketch in
                        SketchRow(number: index + 1, image: sketch.image, editable: sketch.link?.drawing != nil, host: host) {
                            Task { await edit(sketch.image.id, sketch.link) }
                        }
                    }
                }
            }
        }
        .onAppear(perform: adoptPending)
        .fullScreenCover(item: $editing) { editing in
            SketchSheet(initial: editing.drawing, paper: editing.paper,
                        onDone: { drawing, paper in await replace(editing.imageID, drawing, paper) },
                        onCancel: { self.editing = nil })
        }
    }

    private func adoptPending() {
        let ids = Set(noteBody.attachmentIDs)
        let saved = SketchLink.decodeAll(value)
        let missing = PendingSketches.shared.links.filter { ids.contains($0.key) && saved[$0.key] == nil }
        guard !missing.isEmpty else { return }
        value = SketchLink.updating(value, body: noteBody, missing.mapValues { $0 })
    }

    private func edit(_ imageID: String, _ link: SketchLink?) async {
        guard let companion = link?.drawing, let data = try? await host.attachmentData(companion),
              let drawing = try? PKDrawing(data: data) else {
            host.show(String(localized: note.hidden ? "Sketches in hidden notes can't be edited." : "This sketch's drawing couldn't be loaded."),
                      icon: "scribble")
            return
        }
        editing = Editing(imageID: imageID, drawing: drawing, paper: link?.paper ?? .light)
    }

    /// A new image (and drawing) where the old one was; the old files go once nothing references them.
    private func replace(_ oldID: String, _ drawing: PKDrawing, _ paper: Paper) async {
        do {
            guard let (png, link) = try await SketchStore.save(drawing, paper: paper, hidden: note.hidden, host: host) else {
                editing = nil
                return
            }
            let image = try await host.addAttachment(data: png, name: "Sketch.png", contentType: "image/png", kind: .drawing)
            PendingSketches.shared.images[image.id] = image
            let body = SketchGeometry.replacing(oldID, with: image.id, in: noteBody)
            noteBody = body
            value = SketchLink.updating(value, body: body, [oldID: nil, image.id: link])
        } catch {
            host.show(String(localized: "Couldn't save the sketch. Try again."), icon: "exclamationmark.triangle.fill")
        }
        editing = nil
    }
}

struct SketchRow: View {
    let number: Int
    let image: Attachment
    let editable: Bool
    let host: any NotesHost
    let edit: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Nucleus.well)
                .frame(width: 72, height: 56)
                .overlay {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Image(systemName: "scribble.variable").foregroundStyle(Nucleus.secondaryText)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Nucleus.separator))
            VStack(alignment: .leading, spacing: 2) {
                Text("Sketch \(number)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                Text(editable ? "Editable drawing" : "Image only")
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editable {
                Button(action: edit) {
                    Label("Edit sketch", systemImage: "pencil.tip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Nucleus.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Nucleus.accent.opacity(0.12)))
                }
                .buttonStyle(NucleusPressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .task(id: image.id) {
            guard let data = try? await host.attachmentData(image) else { return }
            thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 216, height: 168))
        }
    }
}
