/// The episodes picked in one season: tap one, then a later one to make a range.
struct EpisodeSelection: Equatable {
    var from: Int
    var to: Int

    /// The next unwatched episode; the last one when the season is done.
    static func next(in season: LibraryTitle.Season) -> Self {
        let ep = min(season.watched + 1, season.episodeCount)
        return Self(from: ep, to: ep)
    }

    static func rest(of season: LibraryTitle.Season) -> Self {
        Self(from: min(season.watched + 1, season.episodeCount), to: season.episodeCount)
    }

    static func whole(_ season: LibraryTitle.Season) -> Self { Self(from: 1, to: season.episodeCount) }

    /// A later episode after a single one extends to it; anything else starts over there.
    mutating func tap(_ episode: Int) {
        if from == to, episode > from { to = episode } else { from = episode; to = episode }
    }

    func contains(_ episode: Int) -> Bool { (from...to).contains(episode) }
}

extension LibraryTitle {
    /// Where the picker opens: the first season not finished, else the last.
    var currentSeason: Season? { seasons.first { $0.watched < $0.episodeCount } ?? seasons.last }

    var episodeTotals: (watched: Int, total: Int) {
        seasons.reduce((0, 0)) { ($0.0 + $1.watched, $0.1 + $1.episodeCount) }
    }
}

extension LibraryTitle.Season {
    var title: String { name.isEmpty ? String(localized: "Season \(number)") : name }
    var finished: Bool { watched >= episodeCount }
}
