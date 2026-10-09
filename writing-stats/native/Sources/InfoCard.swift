import NotesPluginKit
import NucleusUI
import SwiftUI

/// The editor's "Info" card: a one-line summary that opens into words, characters, reading time and dates.
struct InfoCard: View {
    let noteBody: NoteBody
    let created: Date
    let edited: Date
    @Binding var expanded: Bool

    var body: some View {
        let info = NoteInfo(body: noteBody)
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(NucleusMotion.quick) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    IconTile("info", tint: .slate, size: 26)
                    Text("Info")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Nucleus.primaryText)
                    Spacer(minLength: 8)
                    if !expanded {
                        Text(summary(info))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Nucleus.secondaryText)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Nucleus.secondaryText)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Info"))
            .accessibilityValue(Text(summary(info)))
            .accessibilityHint(expanded ? Text("Hides the details") : Text("Shows the details"))

            if expanded {
                VStack(spacing: 12) {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Stat(value: info.words.formatted(), label: info.words == 1 ? "word" : "words")
                            Stat(value: info.characters.formatted(), label: "characters")
                            Stat(value: info.readingMinutes == 0 ? "–" : "\(info.readingMinutes) min", label: "reading")
                        }
                    }
                    if info.checklist.total > 0 {
                        ChecklistBar(done: info.checklist.done, total: info.checklist.total)
                    }
                    VStack(spacing: 6) {
                        DateLine(label: "Created", date: created)
                        DateLine(label: "Edited", date: edited)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .nucleusGlass(cornerRadius: 20)
    }

    private func summary(_ info: NoteInfo) -> String {
        let words = info.words == 1 ? String(localized: "1 word") : String(localized: "\(info.words.formatted()) words")
        guard info.readingMinutes > 0 else { return words }
        return words + " · " + String(localized: "\(info.readingMinutes) min read")
    }
}

private struct Stat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Nucleus.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nucleus.well))
    }
}

private struct ChecklistBar: View {
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Checklist", systemImage: "checklist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Nucleus.secondaryText)
                Spacer()
                Text("\(done) of \(total)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(done == total ? Nucleus.success : Nucleus.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nucleus.well)
                    Capsule().fill(done == total ? AnyShapeStyle(Nucleus.success) : AnyShapeStyle(Nucleus.accent))
                        .frame(width: max(6, proxy.size.width * CGFloat(done) / CGFloat(max(total, 1))))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct DateLine: View {
    let label: LocalizedStringKey
    let date: Date

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Nucleus.secondaryText)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(Nucleus.primaryText)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }
}
