import NotesPluginKit
import NucleusUI
import SwiftUI

/// One version: read it, or see how it differs from the note now, and restore it.
struct VersionDetail: View {
    enum Mode: Hashable { case version, changes }

    let version: NoteVersion
    let current: PluginNote
    let back: () -> Void
    let restore: () async -> Void
    @State private var mode = Mode.version
    @State private var restoring = false

    var body: some View {
        ZStack(alignment: .top) {
            NucleusBackground()
            ScrollView {
                VStack(spacing: 16) {
                    NucleusSegmented(selection: $mode, items: [(.version, "This version"), (.changes, "Changes")], fill: true)
                    Group {
                        switch mode {
                        case .version: BodyPreview(title: version.title, noteBody: version.body, attachments: current.attachments)
                        case .changes: DiffView(lines: diff)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nucleusGlass(cornerRadius: NucleusRadius.card)
                }
                .padding(.horizontal, 16)
                .padding(.top, 76)
                .padding(.bottom, 120)
            }
            header
            footer
        }
    }

    private var diff: [TextDiff.Line] {
        TextDiff.lines(from: TextDiff.text(title: version.title, body: version.body, attachments: current.attachments),
                       to: TextDiff.text(title: current.title, body: current.body, attachments: current.attachments))
    }

    private var header: some View {
        HStack {
            GlassCircleButton("chevron.left", action: back)
                .accessibilityLabel("Back")
            Spacer()
            VStack(spacing: 1) {
                Text(version.savedAt, format: .relative(presentation: .named))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Nucleus.primaryText)
                Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(Nucleus.secondaryText)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(alignment: .top) {
            LinearGradient(colors: [Nucleus.base, Nucleus.base.opacity(0.85), Nucleus.base.opacity(0)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var footer: some View {
        VStack {
            Spacer()
            Button {
                restoring = true
                Task {
                    await restore()
                    restoring = false
                }
            } label: {
                Label("Restore this version", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(NucleusPrimaryButtonStyle())
            .disabled(restoring)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 30)
            .background(alignment: .bottom) {
                LinearGradient(colors: [Nucleus.base.opacity(0), Nucleus.base.opacity(0.9), Nucleus.base], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

/// Lines added since the version in green, lines only the version has in red, the rest dimmed.
struct DiffView: View {
    let lines: [TextDiff.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if lines.allSatisfy({ $0.kind == .same }) {
                Label("Same as the note now", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Nucleus.success)
            } else {
                HStack(spacing: 14) {
                    legend("Added since", color: Nucleus.success, sign: "+")
                    legend("Only in this version", color: Nucleus.danger, sign: "−")
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(line) }
                }
            }
        }
    }

    private func legend(_ title: LocalizedStringKey, color: Color, sign: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: sign)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.15)))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
        }
    }

    private func row(_ line: TextDiff.Line) -> some View {
        let color: Color? = switch line.kind {
        case .added: Nucleus.success
        case .removed: Nucleus.danger
        case .same: nil
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color ?? .clear)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .font(.system(size: 15))
                .strikethrough(line.kind == .removed, color: Nucleus.danger.opacity(0.6))
                .foregroundStyle(line.kind == .same ? Nucleus.secondaryText : Nucleus.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color?.opacity(0.12) ?? .clear))
    }
}
