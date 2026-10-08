import Foundation
import TodoPluginKit

/// What a linked task needs next, from its done state and its link alone.
public enum ReconcileStep: Hashable, Sendable {
    case none
    /// Store this link; no network needed.
    case update(WatchLink)
    case sendMark(JSONValue)
    /// Ask the server where the mark command is.
    case poll(String)
    /// Reopened after a mark: just the task, or also unwatch?
    case confirm
    case sendUnmark(JSONValue)
}

/// The link's state machine, pure so it can be tested without a server.
public enum Reconciler {
    public static func step(done: Bool, link: WatchLink) -> ReconcileStep {
        let mark = link.mark
        if done {
            if link.unwatchPending != nil { return .update(cleared(link, dropMark: false)) }
            guard let mark, mark.status != .cancelled else { return link.broken == nil ? .sendMark(markPayload(link)) : .none }
            return mark.status.isSettled ? .none : .poll(mark.id)
        }
        guard let mark else { return link.unwatchPending != nil ? .update(cleared(link, dropMark: true)) : .none }
        switch mark.status {
        case .rejected, .cancelled:
            // Nothing was marked, so nothing to take back.
            return .update(cleared(link, dropMark: true))
        case .pending, .delivered:
            return link.unwatchPending == true ? .poll(mark.id) : .confirm
        case .applied:
            guard link.unwatchPending == true else { return .confirm }
            return mark.previousStatus == nil ? .poll(mark.id) : .sendUnmark(unmarkPayload(link, mark))
        }
    }

    /// The mark command was sent.
    public static func marked(_ link: WatchLink, _ command: CrossAppCommand) -> WatchLink {
        var l = link
        l.mark = .init(id: command.id, status: command.status)
        return polled(l, command)
    }

    /// The server said where the mark command is.
    public static func polled(_ link: WatchLink, _ command: CrossAppCommand) -> WatchLink {
        guard var mark = link.mark, mark.id == command.id else { return link }
        var l = link
        mark.status = command.status
        switch command.status {
        case .applied:
            mark.previousWatched = command.result?["previousWatched"]?.int
            mark.previousStatus = command.result?["previousStatus"]?.string
            mark.watched = command.result?["watched"]?.int
            mark.previousSeasons = command.result?["previousSeasons"]?.array?.compactMap { s in
                guard let n = s["number"]?.int, let w = s["watched"]?.int else { return nil }
                return WatchLink.SeasonCount(number: n, watched: w)
            }
            l.mark = mark
            // Without what Watchlist had before there is nothing to restore.
            if l.unwatchPending == true, mark.previousStatus == nil { l = cleared(l, dropMark: true) }
        case .rejected:
            l.mark = mark
            l.broken = command.result?["reason"]?.string ?? "rejected"
        default:
            l.mark = mark
        }
        return l
    }

    /// "Just the task" (or the dialog dismissed): forget the mark, leave Watchlist alone.
    public static func justTheTask(_ link: WatchLink) -> WatchLink { cleared(link, dropMark: true) }

    /// "Also mark unwatched" cancelled the mark command, or found it too late to.
    public static func cancelled(_ link: WatchLink, _ outcome: CancelOutcome) -> WatchLink {
        guard var mark = link.mark else { return link }
        switch outcome {
        case .cancelled, .notPending(.rejected), .notPending(.cancelled):
            return cleared(link, dropMark: true)
        case .notPending(let status):
            var l = link
            mark.status = status
            l.mark = mark
            l.unwatchPending = true
            return l
        }
    }

    /// The unmark command was sent; Watchlist applies it on its own.
    public static func unmarked(_ link: WatchLink) -> WatchLink { cleared(link, dropMark: true) }

    public static func markPayload(_ link: WatchLink) -> JSONValue {
        var p: [String: JSONValue] = ["itemId": .string(link.itemId)]
        if let season = link.season {
            p["season"] = .number(Double(season))
            if let from = link.fromEp { p["fromEp"] = .number(Double(from)) }
            if let to = link.toEp { p["toEp"] = .number(Double(to)) }
        }
        return .object(p)
    }

    static func unmarkPayload(_ link: WatchLink, _ mark: WatchLink.Mark) -> JSONValue {
        var p: [String: JSONValue] = ["itemId": .string(link.itemId), "restoreStatus": .string(mark.previousStatus ?? "")]
        if let season = link.season {
            p["season"] = .number(Double(season))
            if let before = mark.previousWatched { p["restoreTo"] = .number(Double(before)) }
            // Watchlist refuses the rollback once you've watched past this.
            if let after = mark.watched { p["expectWatched"] = .number(Double(after)) }
        } else if let seasons = mark.previousSeasons, !seasons.isEmpty {
            p["restoreSeasons"] = .array(seasons.map { ["number": .number(Double($0.number)), "watched": .number(Double($0.watched))] })
        }
        return .object(p)
    }

    /// The library shows more of the season watched than the mark left: a rollback would take that too.
    static func watchedPast(_ link: WatchLink, in library: [LibraryTitle]) -> Bool {
        guard let season = link.season, let after = link.mark?.watched,
              let now = library.first(where: { $0.id == link.itemId })?.seasons.first(where: { $0.number == season })?.watched else { return false }
        return now > after
    }

    private static func cleared(_ link: WatchLink, dropMark: Bool) -> WatchLink {
        var l = link
        if dropMark { l.mark = nil }
        l.unwatchPending = nil
        return l
    }
}
