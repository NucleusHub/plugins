import { fetchDetail, posterUrl } from './tmdb.js'

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
