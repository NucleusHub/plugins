// TMDb access for the For You surface. Deliberately the plugin's own thin
// client rather than an import of the host's `@/api/tmdb.js`: this plugin talks
// to endpoints the host has no use for (/recommendations, /discover, the genre
// lists), and keeping the dependency at "the same public API key the host is
// already configured with" is the same arrangement In Common has with
// /api/auth/in-common.
//
// The key is the host app's build-time `VITE_TMDB_API_KEY`. When it's missing
// every call here throws `NoKeyError`, which the surface reports as "the
// discovery half is unavailable" — the local half of the recommendations never
// touches the network and keeps working.

const BASE = 'https://api.themoviedb.org/3'
const KEY = import.meta.env.VITE_TMDB_API_KEY

export class NoKeyError extends Error {
  constructor() {
    super('VITE_TMDB_API_KEY not set')
    this.name = 'NoKeyError'
  }
}

export const hasKey = () => !!KEY

async function get(path, params = {}) {
  if (!KEY) throw new NoKeyError()
  const url = new URL(`${BASE}${path}`)
  url.searchParams.set('api_key', KEY)
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v))
  }
  const res = await fetch(url)
  if (!res.ok) throw new Error(`TMDb ${res.status}`)
  return res.json()
}

// ── Genre maps ───────────────────────────────────────────────────────────────
// TMDb hands back bare `genre_ids` on list endpoints and takes ids on /discover,
// while the watchlist stores genre *names*. These two lists are the bridge, and
// they change about never — cached for a month so a normal session spends no
// requests on them.
const GENRES_KEY = 'watchlist-recs:genres'
const GENRES_TTL = 30 * 24 * 60 * 60 * 1000

let genresPromise = null

async function fetchGenreMaps() {
  const [movie, tv] = await Promise.all([get('/genre/movie/list'), get('/genre/tv/list')])
  return {
    movie: Object.fromEntries((movie.genres ?? []).map((g) => [g.id, g.name])),
    tv: Object.fromEntries((tv.genres ?? []).map((g) => [g.id, g.name])),
  }
}

// { movie: {id: name}, tv: {id: name} } — resolved once per page load.
export function genreMaps() {
  if (genresPromise) return genresPromise
  genresPromise = (async () => {
    try {
      const cached = JSON.parse(localStorage.getItem(GENRES_KEY) || 'null')
      if (cached?.at && Date.now() - cached.at < GENRES_TTL && cached.maps?.movie) return cached.maps
    } catch {
      // fall through to a fetch
    }
    const maps = await fetchGenreMaps()
    try {
      localStorage.setItem(GENRES_KEY, JSON.stringify({ at: Date.now(), maps }))
    } catch {
      // storage full or blocked — the in-memory promise still serves this session
    }
    return maps
  })()
  // Don't cache a rejection: a transient failure shouldn't disable genre names
  // for the rest of the session.
  genresPromise.catch(() => { genresPromise = null })
  return genresPromise
}

// Name → id, per media type. Built from the same maps, for /discover.
export async function genreIdsByName(mediaType) {
  const maps = await genreMaps()
  const out = new Map()
  for (const [id, name] of Object.entries(maps[mediaType] ?? {})) out.set(name.toLowerCase(), Number(id))
  return out
}

// ── Candidate sources ────────────────────────────────────────────────────────

// "More like this" for one title the user finished. The single best signal TMDb
// offers, because it's built from what other people actually watched together
// rather than from genre overlap alone.
export function fetchSimilarTo(tmdbId, mediaType) {
  return get(`/${mediaType}/${tmdbId}/recommendations`).then((d) => d.results ?? [])
}

// Genre-led backfill, for when the seeds are few or their recommendations are
// all already on the list. `voteCountGte` keeps the long tail of obscure
// entries out — TMDb will happily return a 10.0-rated title with four votes.
export function discoverByGenres(mediaType, genreIds, { voteCountGte = 200, page = 1 } = {}) {
  if (!genreIds.length) return Promise.resolve([])
  return get(`/discover/${mediaType}`, {
    with_genres: genreIds.join('|'),
    sort_by: 'popularity.desc',
    'vote_count.gte': voteCountGte,
    include_adult: false,
    page,
  }).then((d) => d.results ?? [])
}

// Full detail for a title the user is adding, so the new item lands with the
// same fields the app's own add flow would have filled in.
export function fetchDetail(tmdbId, mediaType) {
  return get(`/${mediaType}/${tmdbId}`)
}

export const posterUrl = (path, size = 'w500') =>
  path ? `https://image.tmdb.org/t/p/${size}${path}` : null
