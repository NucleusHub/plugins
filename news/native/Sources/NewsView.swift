import NucleusUI
import SwiftUI
import UIKit
import WatchlistPluginKit

/// The News page: For you (what mentions your titles and people, with why) and Everything.
struct NewsView: View {
    enum Tab: Hashable { case forYou, everything }

    let host: any WatchlistHost
    @State private var model = NewsModel.shared
    @State private var tab: Tab = .forYou
    @State private var progress = CarouselProgress()
    /// For you's articles with why; worked out off the main thread when the news or the person's titles change.
    @State private var matched: [MatchedArticle] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let interests = NewsInterests(dna: host.movieDNA, library: host.library)
        ZStack {
            NucleusBackground()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        GlassCircleButton("chevron.left") { dismiss() }.accessibilityLabel("Back")
                        Spacer()
                        menu
                    }
                    .frame(height: 40)
                    Text("News")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Nucleus.primaryText)
                        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 20)
                    SlidingSegmented(selection: Binding(get: { tab }, set: { next in
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { tab = next }
                    }), items: [(Tab.forYou, LocalizedStringKey("For you")), (Tab.everything, LocalizedStringKey("Everything"))], fill: true, progress: progress)
                        .padding(.bottom, 8)
                }
                .padding(.horizontal, 16).padding(.top, 12)
                // Both lists stay loaded and slide with the finger.
                PagedCarousel([Tab.forYou, .everything], selection: Binding(get: { tab }, set: { next in
                    guard next != tab else { return }
                    Haptics.selection()
                    tab = next
                }), progress: progress) { page in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if page == .forYou { forYou(matched) } else { everything }
                            if !model.failedSources.isEmpty, !model.articles.isEmpty {
                                Text("Couldn't reach \(model.failedSources.joined(separator: ", ")).")
                                    .font(.system(size: 12)).foregroundStyle(Nucleus.secondaryText)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
                    }
                    .refreshable { await model.refresh(force: true) }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.refresh() }
        .task(id: MatchKey(articles: model.articles.count, newest: model.articles.first?.id, terms: interests.terms)) {
            let articles = model.articles
            matched = await Task.detached(priority: .userInitiated) {
                articles.compactMap { a in interests.reason(for: a).map { MatchedArticle(article: a, reason: $0) } }
            }.value
        }
        // On Everything a swipe right goes back to For you, so the page-wide back swipe steps aside.
        .background { BackSwipe(enabled: tab == .forYou).frame(width: 0, height: 0) }
    }

    @ViewBuilder
    private func forYou(_ matched: [MatchedArticle]) -> some View {
        if model.articles.isEmpty {
            loadingOrFailed
        } else if matched.isEmpty {
            NucleusEmptyState("newspaper", title: "Nothing about your titles today",
                              message: "Articles that mention your watchlist or people you follow show up here.")
                .frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            NucleusSection {
                ForEach(matched) { m in row(m.article, why: Self.why(m.reason)) }
            }
        }
    }

    @ViewBuilder
    private var everything: some View {
        if model.articles.isEmpty {
            loadingOrFailed
        } else {
            NucleusSection {
                ForEach(model.articles.prefix(150)) { row($0, why: nil) }
            }
        }
    }

    @ViewBuilder
    private var loadingOrFailed: some View {
        if model.loading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        } else {
            NucleusEmptyState("newspaper", title: "Couldn't load the news", message: "Check your connection and pull to try again.")
                .frame(maxWidth: .infinity).padding(.top, 60)
        }
    }

    private var menu: some View {
        Menu {
            Picker("Open articles", selection: Binding(get: { model.openInApp }, set: { model.openInApp = $0 })) {
                Text("In your browser (recommended)").tag(false)
                Text("In the app").tag(true)
            }
            Button { Task { await model.refresh(force: true) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Nucleus.glyph)
                .frame(width: 40, height: 40)
                .nucleusGlass(in: Circle(), interactive: true)
        }
        .accessibilityLabel("More")
    }

    private func row(_ article: Article, why: Text?) -> some View {
        SwipeSafeButton { host.open(.web(article.link, inApp: model.openInApp)) } label: {
            ArticleRow(article: article, why: why)
        }
        .buttonStyle(NucleusRowButtonStyle())
    }

    static func why(_ reason: NewsReason) -> Text {
        switch reason {
        case .following(let name): Text("Mentions \(name), whom you follow")
        case .person(let name): Text("Mentions \(name), from your MovieDNA")
        case .watchlist(let title): Text("About \(title), on your watchlist")
        case .movieDNA(let title): Text("About \(title), from your MovieDNA")
        }
    }
}

/// Headline, then source and when, then why it's here.
struct ArticleRow: View {
    let article: Article
    let why: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: article.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Nucleus.primaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            HStack(spacing: 4) {
                Text(verbatim: article.source)
                if let date = article.date {
                    Text(verbatim: "·")
                    Text(date, format: .relative(presentation: .named))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Nucleus.secondaryText)
            if let why {
                why.font(.system(size: 13, weight: .medium)).foregroundStyle(Nucleus.accent).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// "In the news" on a person's page: articles that mention them by name.
struct PersonNewsView: View {
    let name: String
    let host: any WatchlistHost
    @State private var model = NewsModel.shared

    var body: some View {
        let mentions = model.articles.filter { NewsInterests.contains($0.title + " " + $0.summary, name, caseSensitive: false) }
        Group {
            if !mentions.isEmpty {
                NucleusSection("In the news") {
                    ForEach(mentions.prefix(5)) { article in
                        SwipeSafeButton { host.open(.web(article.link, inApp: model.openInApp)) } label: { ArticleRow(article: article, why: nil) }
                            .buttonStyle(NucleusRowButtonStyle())
                    }
                }
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .task { await model.refresh() }
    }
}

/// Turns the navigation controller's swipe-back-from-anywhere on or off; the edge swipe always stays.
private struct BackSwipe: UIViewControllerRepresentable {
    let enabled: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enabled = enabled
        controller.apply()
    }

    final class Controller: UIViewController {
        var enabled = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if #available(iOS 26, *) { navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = true }
        }

        func apply() {
            if #available(iOS 26, *) { navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled }
        }
    }
}

/// A button that ignores the tap when the finger dragged first, so swiping between tabs over a headline
/// doesn't open it. Same as the app's: the watcher notices the move and steps aside, so swipes aren't held up.
struct SwipeSafeButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var dragged = false

    var body: some View {
        let button = Button { if !dragged { action() } } label: { label }
        if #available(iOS 18, *) {
            button.gesture(MoveWatcher(touched: { dragged = false }, moved: { dragged = true }))
        } else {
            button.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in dragged = true }.onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { dragged = false }
            })
        }
    }
}

@available(iOS 18, *)
private struct MoveWatcher: UIGestureRecognizerRepresentable {
    let touched: () -> Void
    let moved: () -> Void

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let recognizer = Recognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
        recognizer.touched = touched
        recognizer.moved = moved
    }

    final class Recognizer: UIGestureRecognizer {
        var touched: () -> Void = {}
        var moved: () -> Void = {}
        private var start: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            start = touches.first?.location(in: view)
            touched()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) {
                moved()
                state = .failed
            }
        }

        // A fast flick can end before any move reaches here, so the distance is checked at the end too.
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) { moved() }
            state = .failed
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            if travelled(touches) { moved() }
            state = .failed
        }

        override func reset() { start = nil }

        // Never pushed out by the page's swipe, which would otherwise stop it from seeing the move.
        override func canBePrevented(by preventing: UIGestureRecognizer) -> Bool { false }
        override func canPrevent(_ prevented: UIGestureRecognizer) -> Bool { false }

        private func travelled(_ touches: Set<UITouch>) -> Bool {
            guard let start, let now = touches.first?.location(in: view) else { return false }
            return hypot(now.x - start.x, now.y - start.y) > 10
        }
    }
}

struct MatchedArticle: Identifiable, Sendable {
    let article: Article
    let reason: NewsReason
    var id: String { article.id }
}

/// What For you's matches depend on.
private struct MatchKey: Equatable {
    let articles: Int
    let newest: String?
    let terms: [NewsInterests.Term]
}
