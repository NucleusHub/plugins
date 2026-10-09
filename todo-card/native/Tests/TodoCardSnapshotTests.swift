import NotesPluginKit
import NucleusUI
import SwiftUI
import UIKit
import XCTest
@testable import TodoCardPlugin

/// Renders the card to PNGs for a look (not compared against anything).
@MainActor
final class TodoCardSnapshotTests: XCTestCase {
    static let folder = URL(fileURLWithPath: "/private/tmp/claude-501/shots")

    func testRendersTheCard() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            try render(TodoCardPreview(scrolls: false), name: "card", style: style)
        }
    }

    func testRendersAnOfflineCard() throws {
        let host = TodoSamples.host()
        host.client.failViews = .network
        var data = TodoCardData()
        data = TodoCardLogic.attach(TodoSamples.inbox, to: data, now: Date().addingTimeInterval(-3 * 3600))
        try render(TodoCardPreview(data: data, host: host, scrolls: false, offlineSince: Date().addingTimeInterval(-3 * 3600)),
                   name: "offline", style: .light)
    }

    func testRendersThePicker() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            // The sheet's ScrollView doesn't render here, so this is the list it scrolls.
            let rows = TodoListRows(lists: [TodoSamples.inbox, TodoSamples.groceries, TodoSamples.trip], attached: ["inbox"], onPick: { _ in })
                .padding(16)
                .background { NucleusBackground() }
            try render(rows, name: "picker", style: style)
        }
    }

    /// ImageRenderer, since a package test has no window scene to draw a hosting controller into. It leaves
    /// Liquid Glass (iOS 26+) blank, so files are written only on the iOS 17 simulator (iPhone 15 Pro, 393pt wide).
    private func render(_ view: some View, name: String, style: UIUserInterfaceStyle, height: CGFloat? = nil) throws {
        let scheme: ColorScheme = style == .dark ? .dark : .light
        let content = view
            .fixedSize(horizontal: false, vertical: height == nil)
            .frame(width: 393, height: height)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 393, height: height)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: style).performAsCurrent { image = renderer.uiImage }
        let png = try XCTUnwrap(image?.pngData())
        if #available(iOS 26, *) { return }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try png.write(to: Self.folder.appendingPathComponent("plugin-todo-card-\(name)-\(style == .dark ? "dark" : "light").png"))
    }
}
