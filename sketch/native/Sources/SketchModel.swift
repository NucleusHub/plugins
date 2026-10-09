import CoreGraphics
import Foundation
import NotesPluginKit

/// The sheet a sketch is drawn and exported on.
enum Paper: String, CaseIterable, Sendable {
    case light, dark, grid
}

enum SketchGeometry {
    /// The part of the canvas to export: the drawing's bounds plus padding, at least `minSide` each way, on whole points.
    static func exportRect(drawingBounds: CGRect, padding: CGFloat = 24, minSide: CGFloat = 160) -> CGRect? {
        guard !drawingBounds.isNull, !drawingBounds.isInfinite, drawingBounds.width > 0 || drawingBounds.height > 0 else { return nil }
        var rect = drawingBounds.insetBy(dx: -padding, dy: -padding)
        if rect.width < minSide { rect = rect.insetBy(dx: -(minSide - rect.width) / 2, dy: 0) }
        if rect.height < minSide { rect = rect.insetBy(dx: 0, dy: -(minSide - rect.height) / 2) }
        return rect.integral
    }

    /// 2× unless that makes the long side more than `maxPixels`.
    static func scale(for rect: CGRect, preferred: CGFloat = 2, maxPixels: CGFloat = 4096) -> CGFloat {
        let long = max(rect.width, rect.height)
        guard long > 0 else { return preferred }
        return min(preferred, maxPixels / long)
    }

    /// The body with the image block of `old` showing `new` instead, in the same place.
    static func replacing(_ old: String, with new: String, in body: NoteBody) -> NoteBody {
        var out = body
        for i in out.blocks.indices where out.blocks[i].attachment == old { out.blocks[i].attachment = new }
        return out
    }
}

/// A sketch's editable data, kept in plugin data keyed by its image attachment id:
/// `{imageId: {"drawing": <companion attachment>, "paper": "grid"}}`.
/// The whole companion attachment is kept because no block shows it, so the note's attachments don't list it.
struct SketchLink: Hashable, Sendable {
    var drawing: Attachment?
    var paper: Paper

    static func decodeAll(_ value: JSONValue?) -> [String: SketchLink] {
        guard let object = value?.object else { return [:] }
        return object.compactMapValues { entry in
            guard entry.object != nil else { return nil }
            return SketchLink(drawing: try? entry["drawing"]?.decode(Attachment.self),
                              paper: entry["paper"]?.string.flatMap(Paper.init(rawValue:)) ?? .light)
        }
    }

    static func encodeAll(_ links: [String: SketchLink]) -> JSONValue? {
        guard !links.isEmpty else { return nil }
        return .object(links.mapValues { link in
            var entry: [String: JSONValue] = ["paper": .string(link.paper.rawValue)]
            if let drawing = link.drawing, let json = try? JSONValue(encoding: drawing) { entry["drawing"] = json }
            return .object(entry)
        })
    }

    /// Links for images still in the body, with `changes` applied (nil removes).
    static func updating(_ value: JSONValue?, body: NoteBody, _ changes: [String: SketchLink?]) -> JSONValue? {
        var all = decodeAll(value)
        for (id, link) in changes { all[id] = link }
        let ids = Set(body.attachmentIDs)
        return encodeAll(all.filter { ids.contains($0.key) })
    }
}

/// Links made by the insert action before the note saved them (it can't write the plugin data binding).
@MainActor
final class PendingSketches {
    static let shared = PendingSketches()
    var links: [String: SketchLink] = [:]
    var images: [String: Attachment] = [:]
}
