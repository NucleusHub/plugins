import Charts
import NotesPluginKit
import NucleusUI
import SwiftUI

/// Settings → Notes → "Writing statistics".
struct StatsRow: View {
    let host: any NotesHost
    @State private var showing = false

    var body: some View {
        Button {
            Haptics.tap()
            showing = true
        } label: {
            NucleusRow("Writing statistics", subtitle: Text("Words, notes per week and your streak"),
                       icon: IconTile("chart.bar.fill", tint: .violet)) { Chevron() }
        }
        .buttonStyle(NucleusRowButtonStyle())
        .sheet(isPresented: $showing) {
            NucleusSheetPage("Writing statistics", onCancel: { showing = false }) {
                StatsContent(host: host, ledger: LedgerStore.shared.ledger) { id in
                    showing = false
                    host.open(noteID: id)
                }
            }
        }
    }
}

/// The statistics: tiles, notes per week, tags, the longest note.
struct StatsContent: View {
    let host: any NotesHost
    let ledger: WordLedger
    var now = Date()
    var open: (String) -> Void = { _ in }

    var body: some View {
        let stats = StatsSummary(notes: host.notes.filter { !$0.hidden }, ledger: ledger, now: now)
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Tile(value: stats.totalNotes, label: stats.totalNotes == 1 ? "note" : "notes", icon: "note.text", tint: .indigo)
                    Tile(value: stats.totalWords, label: "words in all", icon: "text.alignleft", tint: .sky)
                }
                GridRow {
                    Tile(value: stats.wordsThisWeek, label: "written this week", icon: "pencil.line", tint: .emerald)
                    Tile(value: stats.streak, label: "day streak", icon: "flame.fill", tint: .orange)
                }
            }
            .padding(.bottom, 28)

            NucleusSection("Notes created per week", footer: Text("The last 14 weeks.")) {
                WeeksChart(weeks: stats.weeks)
                    .frame(height: 170)
                    .padding(16)
            }

            if !stats.topTags.isEmpty {
                NucleusSection("Most-used tags") {
                    ForEach(Array(stats.topTags.enumerated()), id: \.offset) { _, entry in
                        NucleusRow(verbatim: "#\(entry.tag)", icon: IconTile("number", tint: .teal)) {
                            Text("\(entry.count)")
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Nucleus.secondaryText)
                        }
                    }
                }
            }

            if let longest = stats.longest {
                NucleusSection("Longest note") {
                    Button { open(longest.id) } label: {
                        NucleusRow(verbatim: longest.title, subtitle: Text("\(longest.words.formatted()) words"),
                                   icon: IconTile("text.book.closed.fill", tint: .amber)) { Chevron() }
                    }
                    .buttonStyle(NucleusRowButtonStyle())
                }
            }

            Text("Words written are counted on this device from when the plugin was turned on. Hidden notes aren't counted.")
                .font(.system(size: 13))
                .foregroundStyle(Nucleus.secondaryText)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Tile: View {
    let value: Int
    let label: LocalizedStringKey
    let icon: String
    let tint: NucleusTint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(icon, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted())
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Nucleus.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(Nucleus.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .nucleusGlass(cornerRadius: 20)
    }
}

private struct WeeksChart: View {
    let weeks: [StatsSummary.Week]

    var body: some View {
        let peak = max(weeks.map(\.notes).max() ?? 0, 4)
        Chart {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Notes", week.notes), width: .ratio(0.62))
                    .foregroundStyle(index == weeks.count - 1 ? AnyShapeStyle(Nucleus.accent) : AnyShapeStyle(Nucleus.accent.opacity(0.45)))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .chartYScale(domain: 0...peak)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Nucleus.separator)
                AxisValueLabel().foregroundStyle(Nucleus.secondaryText)
            }
        }
        .chartXAxis {
            AxisMarks(values: weeks.enumerated().filter { $0.offset % 4 == 1 }.map(\.element.start)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true).foregroundStyle(Nucleus.secondaryText)
            }
        }
        .accessibilityLabel(Text("Notes created per week"))
    }
}
