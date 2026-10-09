@testable import SketchPlugin
import NotesPluginKit
import NucleusUI
import PencilKit
import SwiftUI
import XCTest

private func sampleDrawing() -> PKDrawing {
    let points = (0..<30).map { i in
        PKStrokePoint(location: CGPoint(x: 100 + Double(i) * 8, y: 200 + sin(Double(i) / 3) * 40), timeOffset: Double(i) * 0.01,
                      size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }
    return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: .now))])
}

final class SketchGeometryTests: XCTestCase {
    func testExportRectPadsAndTrims() {
        XCTAssertEqual(SketchGeometry.exportRect(drawingBounds: CGRect(x: 100, y: 200, width: 300, height: 200)),
                       CGRect(x: 76, y: 176, width: 348, height: 248))
    }

    func testExportRectGrowsTinyDrawingsAroundTheirCenter() {
        let rect = SketchGeometry.exportRect(drawingBounds: CGRect(x: 50, y: 50, width: 10, height: 0))!
        XCTAssertEqual(rect.width, 160)
        XCTAssertEqual(rect.height, 160)
        XCTAssertEqual(rect.midX, 55, accuracy: 0.5)
        XCTAssertEqual(rect.midY, 50, accuracy: 0.5)
    }

    func testEmptyDrawingHasNoRect() {
        XCTAssertNil(SketchGeometry.exportRect(drawingBounds: .null))
        XCTAssertNil(SketchGeometry.exportRect(drawingBounds: .zero))
    }

    func testScaleCapsHugeDrawings() {
        XCTAssertEqual(SketchGeometry.scale(for: CGRect(x: 0, y: 0, width: 400, height: 300)), 2)
        XCTAssertEqual(SketchGeometry.scale(for: CGRect(x: 0, y: 0, width: 4096, height: 100)), 1)
    }

    func testReplacingKeepsThePlace() {
        let body = NoteBody(blocks: [Block(text: "a"), Block(.image, attachment: "old"), Block(text: "b")])
        let out = SketchGeometry.replacing("old", with: "new", in: body)
        XCTAssertEqual(out.blocks.map(\.attachment), [nil, "new", nil])
        XCTAssertEqual(out.blocks.map(\.id), body.blocks.map(\.id))
    }
}

final class SketchLinkTests: XCTestCase {
    func testRoundTripAndUpdating() {
        let companion = Attachment(id: "d1", name: "Sketch.drawing", contentType: "application/x-pkdrawing", size: 10, sha256: "ab", kind: .file)
        let value = SketchLink.encodeAll(["img1": SketchLink(drawing: companion, paper: .grid), "img2": SketchLink(drawing: nil, paper: .dark)])
        let decoded = SketchLink.decodeAll(value)
        XCTAssertEqual(decoded["img1"]?.drawing, companion)
        XCTAssertEqual(decoded["img1"]?.paper, .grid)
        XCTAssertNil(decoded["img2"]?.drawing)
        let body = NoteBody(blocks: [Block(.image, attachment: "img3"), Block(.image, attachment: "img2")])
        let updated = SketchLink.decodeAll(SketchLink.updating(value, body: body, ["img2": nil, "img3": SketchLink(drawing: companion, paper: .light)]))
        XCTAssertEqual(Set(updated.keys), ["img3"], "removed, added, and links of images no longer in the body dropped")
        XCTAssertNil(SketchLink.encodeAll([:]))
        XCTAssertTrue(SketchLink.decodeAll(.object(["x": "junk"])).isEmpty)
    }
}

@MainActor
final class SketchFlowTests: XCTestCase {
    func testExportsAPNGTrimmedToTheDrawing() throws {
        let drawing = sampleDrawing()
        let png = try XCTUnwrap(SketchExporter.png(drawing, paper: .dark))
        let image = try XCTUnwrap(UIImage(data: png))
        let rect = SketchGeometry.exportRect(drawingBounds: drawing.bounds)!
        XCTAssertEqual(image.size.width * image.scale, rect.width * 2, accuracy: 1)
        XCTAssertNil(SketchExporter.png(PKDrawing(), paper: .light))
    }

    func testInsertKeepsTheDrawingNextToTheImage() async throws {
        let current = note("n", title: "Ideas")
        let host = FakeHost(notes: [current])
        var inserted: [Block] = []
        await SketchInsertAction().insert(sampleDrawing(), .grid, InsertContext(note: current, host: host, insert: { inserted += $0 }, append: { _ in }))
        XCTAssertEqual(inserted.map(\.type), [.image])
        let imageID = try XCTUnwrap(inserted.first?.attachment)
        let link = try XCTUnwrap(SketchLink.decodeAll(host.pluginData["n"]?["sketch"] ?? nil)[imageID])
        XCTAssertEqual(link.paper, .grid)
        let companion = try XCTUnwrap(link.drawing)
        XCTAssertEqual(companion.contentType, "application/x-pkdrawing")
        XCTAssertEqual(try PKDrawing(data: host.stored[companion.id]!).strokes.count, 1)
        XCTAssertEqual(PendingSketches.shared.images[imageID]?.kind, .drawing)
    }

    func testHiddenNotesKeepOnlyTheImage() async throws {
        let current = note("h", title: "Secret", hidden: true)
        let host = FakeHost(notes: [current])
        var inserted: [Block] = []
        await SketchInsertAction().insert(sampleDrawing(), .light, InsertContext(note: current, host: host, insert: { inserted += $0 }, append: { _ in }))
        XCTAssertEqual(host.stored.count, 1)
        let imageID = try XCTUnwrap(inserted.first?.attachment)
        XCTAssertNil(SketchLink.decodeAll(host.pluginData["h"]?["sketch"] ?? nil)[imageID]?.drawing)
    }
}

@MainActor
final class SketchSnapshots: XCTestCase {
    func testSection() throws {
        let host = FakeHost()
        let image = Attachment(id: "img", name: "Sketch.png", contentType: "image/png", size: 1, sha256: "", kind: .drawing)
        host.stored["img"] = SketchExporter.png(sampleDrawing(), paper: .grid)
        let companion = Attachment(id: "d", name: "Sketch.drawing", contentType: "application/x-pkdrawing", size: 1, sha256: "", kind: .file)
        let body = NoteBody(blocks: [Block(.image, attachment: "img")])
        let n = note("n", title: "Ideas", body: body, attachments: [image])
        try snapshot("plugin-sketch-section") {
            SketchesSection(note: n, host: host, noteBody: .constant(body),
                            value: .constant(SketchLink.encodeAll(["img": SketchLink(drawing: companion, paper: .grid)])))
                .padding(16)
                .background(NucleusBackground())
        }
    }
}
