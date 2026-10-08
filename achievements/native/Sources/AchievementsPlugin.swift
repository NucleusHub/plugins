import NucleusPlugins
import NucleusUI
import SwiftUI
import TodoPluginKit

/// Achievements: badges for streaks, finished tasks, focus time and more.
public struct AchievementsPlugin: Plugin {
    public let manifest: PluginManifest

    public init() {
        manifest = (try? PluginManifest.load(from: Bundle.module)) ?? PluginManifest(
            id: "achievements", name: "Achievements", version: "1.0.0", target: ["todo"]
        )
    }

    public func register(with registrar: PluginRegistrar) {
        registrar.contribute(to: .appEvents, id: "achievements", AchievementEvents() as any AppEvents)
        registrar.contribute(to: .statsCards, id: "achievements", AchievementsCard() as any PluginStatsCard)
    }
}

struct AchievementEvents: AppEvents {
    @MainActor func tasksChanged(host: any TodoHost) { Achievements.shared.update(host: host) }
    @MainActor func dayCompleted(host: any TodoHost) { Achievements.shared.dayCompleted(host: host) }
    @MainActor func reset() { Achievements.shared.reset() }
}

struct AchievementsCard: PluginStatsCard {
    var title: LocalizedStringResource { "Achievements" }
    var icon: String { "trophy.fill" }
    var tint: NucleusTint { .amber }
    var defaultSize: StatsCardSize { .large }

    @MainActor
    func view(size: StatsCardSize, shown: Double, host: any TodoHost) -> AnyView {
        AnyView(AchievementsCardView(size: size, shown: shown, host: host))
    }
}

private struct AchievementsCardView: View {
    let size: StatsCardSize
    let shown: Double
    let host: any TodoHost

    var body: some View {
        let book = Achievements.shared
        let all = Achievement.available(host)
        let count = all.filter { book.unlocked[$0.id] != nil }.count
        Group {
            if size == .small {
                StatsTile("Achievements", value: Double(count), detail: String(localized: "of \(all.count) unlocked"), icon: "trophy.fill", tint: .amber, shown: shown) { "\(Int($0.rounded()))" }
            } else {
                StatsSection("Achievements", footer: Text("\(count) of \(all.count) unlocked")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 16) {
                        ForEach(all) { a in
                            Badge(achievement: a, unlockedAt: book.unlocked[a.id], progress: a.progress(book.facts), shown: shown)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { book.prime(host: host) }
    }
}

/// One achievement: a gradient medal when unlocked, a grey one with a progress ring before.
private struct Badge: View {
    let achievement: Achievement
    let unlockedAt: Date?
    let progress: Int
    let shown: Double

    var body: some View {
        let done = unlockedAt != nil
        let fraction = min(1, Double(progress) / Double(achievement.target))
        VStack(spacing: 6) {
            ZStack {
                if done {
                    Circle().fill(achievement.tint.gradient)
                        .shadow(color: achievement.tint.color.opacity(0.5), radius: 8, y: 3)
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(3)
                } else {
                    Circle().fill(Nucleus.well)
                    Circle()
                        .trim(from: 0, to: fraction * shown)
                        .stroke(achievement.tint.color.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                        .opacity(fraction > 0 ? 1 : 0)
                }
                Image(systemName: achievement.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(done ? .white : Nucleus.secondaryText.opacity(0.7))
            }
            .frame(width: 58, height: 58)
            .scaleEffect(done ? 0.85 + 0.15 * shown : 1)
            Text(achievement.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(done ? Nucleus.primaryText : Nucleus.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(done ? unlockedAt!.formatted(.dateTime.day().month(.abbreviated)) : "\(min(progress, achievement.target))/\(achievement.target)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Nucleus.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(achievement.title))
        .accessibilityValue(done ? Text("Unlocked") : Text("\(min(progress, achievement.target)) of \(achievement.target)"))
        .accessibilityHint(Text(achievement.detail))
        .help(Text(achievement.detail))
        .contextMenu { Text(achievement.detail) }
    }
}
