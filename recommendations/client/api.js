// Adding a discovered title to the watchlist. Goes through the app's own public
// HTTP surface (`/api/watchlist`) rather than importing the host's api module,
// so the plugin stays a separate package that happens to be bundled alongside
// it — the same arrangement In Common has with `/api/auth/in-common`.

import { fetchDetail, posterUrl } from './tmdb.js'

// Build the item body from a discovery candidate, enriched with the detail
// payload so a title added from here arrives with the same fields the app's own
// add flow would have filled in — runtime, season/episode counts, the streaming
// provider are all things the list endpoints don't carry. A detail fetch that
// fails is not worth failing the add over: the item still lands, and the app's
// Refresh button fills the rest in later.
async function buildItem(candidate) {
  const base = {
    title: candidate.title,
    type: candidate.type,
    status: 'planned',
    tmdbId: candidate.tmdbId,
    posterUrl: posterUrl(candidate.posterPath),
    year: candidate.year,
    tmdbRating: candidate.tmdbRating,
    genres: candidate.genres,
  }

  let detail
  try {
    detail = await fetchDetail(candidate.tmdbId, candidate.mediaType)
  } catch {
    return base
  }

  // Prefer the detail payload's genre names: they're the same vocabulary the
  // host's TMDb source writes, where the list endpoints' `genre_ids` had to be
  // mapped through a cached lookup that can be missing an id.
  const detailGenres = (detail.genres ?? []).map((g) => g.name).filter(Boolean)
  if (detailGenres.length) base.genres = detailGenres

  if (candidate.mediaType === 'movie') {
    if (detail.runtime) base.runtime = detail.runtime
  } else {
    if (detail.number_of_seasons) base.seasons = detail.number_of_seasons
    if (detail.number_of_episodes) base.episodes = detail.number_of_episodes
    if (detail.number_of_episodes && detail.episode_run_time?.length) {
      base.showRuntime = detail.number_of_episodes * detail.episode_run_time[0]
    }
    base.seasonProgress = (detail.seasons ?? [])
      .filter((s) => s.season_number > 0 && s.episode_count > 0)
      .sort((a, b) => a.season_number - b.season_number)
      .map((s) => ({
        seasonNumber: s.season_number,
        name: s.name || `Season ${s.season_number}`,
        episodeCount: s.episode_count,
        watched: 0,
      }))
  }
  return base
}

export async function addToWatchlist(candidate) {
  const body = await buildItem(candidate)
  const res = await fetch('/api/watchlist', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`Add failed (${res.status})`)
  return res.json()
}
