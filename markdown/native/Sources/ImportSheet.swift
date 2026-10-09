import NotesPluginKit
import NucleusUI
import SwiftUI
import UniformTypeIdentifiers

/// A picked file's name and text.
struct ImportedFile: Sendable {
    let name: String
    let text: String
}

/// Picks `.md`/`.txt` files: opens the document picker at once, with a page behind it to pick again or cancel.
struct ImportSheet: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let multiple: Bool
    let onCancel: () -> Void
    let onFiles: ([ImportedFile]) -> Void

    @State private var picking = false
    @State private var failed: [String] = []

    static let types: [UTType] = [UTType("net.daringfireball.markdown"), UTType(filenameExtension: "md"), .plainText]
        .compactMap { $0 }

    var body: some View {
        NucleusSheetPage(title, onCancel: onCancel) {
            content
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.types, allowsMultipleSelection: multiple) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            let (files, bad) = Self.read(urls)
            failed = bad
            if !files.isEmpty { onFiles(files) }
        }
        .task {
            // Straight to the picker; the page stays behind for a second try.
            try? await Task.sleep(for: .milliseconds(350))
            picking = true
        }
    }

    var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(NucleusTint.slate.gradient)
                        .frame(width: 76, height: 76)
                        .shadow(color: NucleusTint.slate.color.opacity(0.35), radius: 12, y: 6)
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Nucleus.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)

            Button {
                Haptics.tap()
                picking = true
            } label: {
                Label(multiple ? "Choose files" : "Choose a file", systemImage: "folder")
            }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .padding(.bottom, 24)

            if !failed.isEmpty {
                NucleusSection(footer: Text("Only UTF-8 or Latin text files can be read.")) {
                    ForEach(failed, id: \.self) { name in
                        NucleusRow(verbatim: name, subtitle: Text("Couldn't read this file"),
                                   icon: IconTile("exclamationmark.triangle.fill", tint: .rose))
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(["md", "markdown", "txt"], id: \.self) { ext in
                    Text(verbatim: ".\(ext)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Nucleus.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Nucleus.well))
                }
            }
        }
    }

    static func read(_ urls: [URL]) -> ([ImportedFile], [String]) {
        var files: [ImportedFile] = []
        var failed: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let text = MarkdownFile.decode(data) {
                files.append(ImportedFile(name: url.lastPathComponent, text: text))
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        return (files, failed)
    }
}
