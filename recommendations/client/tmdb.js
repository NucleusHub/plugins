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

export function genreMaps() {
  if (genresPromise) return genresPromise
  genresPromise = (async () => {
    try {
      const cached = JSON.parse(localStorage.getItem(GENRES_KEY) || 'null')
      if (cached?.at && Date.now() - cached.at < GENRES_TTL && cached.maps?.movie) return cached.maps
    } catch {
    }
    const maps = await fetchGenreMaps()
    try {
      localStorage.setItem(GENRES_KEY, JSON.stringify({ at: Date.now(), maps }))
    } catch {
    }
    return maps
  })()
  // Don't cache a rejection.
  genresPromise.catch(() => { genresPromise = null })
  return genresPromise
}

export async function genreIdsByName(mediaType) {
  const maps = await genreMaps()
  const out = new Map()
  for (const [id, name] of Object.entries(maps[mediaType] ?? {})) out.set(name.toLowerCase(), Number(id))
  return out
}

export function fetchSimilarTo(tmdbId, mediaType) {
  return get(`/${mediaType}/${tmdbId}/recommendations`).then((d) => d.results ?? [])
}

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

export function fetchDetail(tmdbId, mediaType) {
  return get(`/${mediaType}/${tmdbId}`)
}

export const posterUrl = (path, size = 'w500') =>
  path ? `https://image.tmdb.org/t/p/${size}${path}` : null
