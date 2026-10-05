import NucleusUI
import SwiftUI
import WatchlistPluginKit

/// Cards that snap one at a time, with dots under them.
struct JumpBackInView: View {
    let titles: [PluginTitle]
    let canResume: Bool
    let resume: @MainActor (String) -> Void
    @State private var current: String?

    var body: some View {
        if canResume, !titles.isEmpty {
            let selected = titles.firstIndex { $0.id == current } ?? 0
            VStack(alignment: .leading, spacing: 10) {
                Text("Jump back in")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Nucleus.secondaryText)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(titles) { title in
                            JumpCard(title: title, resume: resume)
                                .padding(.horizontal, 16)
                                .containerRelativeFrame(.horizontal)
                                .id(title.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)
                if titles.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(titles.indices, id: \.self) { i in
                            Circle()
                                .fill(i == selected ? Nucleus.accent : Nucleus.secondaryText.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .animation(NucleusMotion.quick, value: selected)
                    .accessibilityHidden(true)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }
}

private struct JumpCard: View {
    let title: PluginTitle
    let resume: @MainActor (String) -> Void

    var body: some View {
        Button {
            Haptics.tap()
            resume(title.id)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: title.posterURL) { $0.resizable().scaledToFill() } placeholder: { Nucleus.well }
                    .frame(width: 52, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nucleus.primaryText)
                        .lineLimit(2)
                    Text(verbatim: subtitle)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Nucleus.secondaryText)
                        .lineLimit(1)
                    if let resume = title.resume {
                        ProgressView(value: resume.fraction).tint(Color(hex: 0x2A78D6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Nucleus.accent))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .nucleusGlass(cornerRadius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(NucleusPressStyle())
        .accessibilityLabel(Text("Continue watching \(title.title)"))
    }

    private var subtitle: String {
        var parts: [String] = []
        if title.kind == .show, let next = title.nextEpisode { parts.append("S\(next.season) E\(next.episode)") }
        if let resume = title.resume {
            parts.append("\(clock(resume.position)) / \(clock(resume.duration))")
        } else if let host = title.resumeHost {
            parts.append(host)
        }
        return parts.joined(separator: " · ")
    }

    private func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}
