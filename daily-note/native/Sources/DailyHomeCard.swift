import NotesPluginKit
import NucleusUI
import SwiftUI

/// The Notes page card: today's note, this week's days with a daily note, and the streak.
struct DailyHomeCard: View {
    let host: any NotesHost
    var now: Date = Date()
    var math = DayMath()

    var body: some View {
        let days = DailyNotes.days(in: host.notes)
        let today = DailyNotes.note(for: math.key(for: now), in: host.notes)
        let streak = math.streak(days: days, today: now)
        Button {
            Haptics.tap()
            DailyNotes.openToday(host: host, now: now, math: math)
        } label: {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(today == nil ? "sun.max.fill" : "book.fill", tint: .amber, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's note")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Nucleus.primaryText)
                        subtitle(today)
                            .font(.system(size: 13))
                            .foregroundStyle(Nucleus.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StreakBadge(days: streak)
                }
                WeekStrip(days: days, now: now, math: math)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: NucleusRadius.card, style: .continuous)
                    .fill(LinearGradient(colors: [NucleusTint.amber.color.opacity(0.16), NucleusTint.orange.color.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .nucleusGlass(cornerRadius: NucleusRadius.card, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: NucleusRadius.card, style: .continuous))
        }
        .buttonStyle(NucleusPressStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Today's note"))
        .accessibilityValue(Text(streak == 1 ? "1 day streak" : "\(streak) day streak"))
        .accessibilityHint(today == nil ? Text("Starts today's note") : Text("Opens today's note"))
    }

    private func subtitle(_ today: PluginNote?) -> Text {
        let date = now.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard let today else { return Text("\(date) · Tap to start") }
        let words = today.body.wordCount
        return Text("\(date) · \(words == 1 ? String(localized: "1 word") : String(localized: "\(words) words"))")
    }
}

/// The flame and the number of days in a row; gray before the first day.
private struct StreakBadge: View {
    let days: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(days > 0 ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFBBF24), Color(hex: 0xF97316)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Nucleus.secondaryText))
                Text("\(days)")
                    .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Nucleus.primaryText)
                    .contentTransition(.numericText())
            }
            Text("streak")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Nucleus.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(NucleusTint.amber.color.opacity(days > 0 ? 0.14 : 0.06)))
    }
}

/// Monday to Sunday: a filled day had a daily note, today has a ring.
private struct WeekStrip: View {
    let days: Set<String>
    let now: Date
    let math: DayMath

    var body: some View {
        let week = math.week(containing: now)
        let todayKey = math.key(for: now)
        HStack(spacing: 0) {
            ForEach(week, id: \.self) { day in
                let key = math.key(for: day)
                let isToday = key == todayKey
                let written = days.contains(key)
                let future = key > todayKey
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isToday ? NucleusTint.amber.color : Nucleus.secondaryText)
                    ZStack {
                        if written {
                            Circle().fill(NucleusTint.amber.gradient)
                                .shadow(color: NucleusTint.amber.color.opacity(0.35), radius: 4, y: 2)
                        } else {
                            Circle().fill(Nucleus.well)
                        }
                        if isToday {
                            Circle().strokeBorder(NucleusTint.amber.color, lineWidth: 2).padding(-4)
                        }
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(written ? .white : Nucleus.primaryText.opacity(future ? 0.3 : 0.7))
                    }
                    .frame(width: 30, height: 30)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
