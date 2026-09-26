import { fetchSimilarTo, discoverByGenres, genreMaps, genreIdsByName, hasKey, NoKeyError } from './tmdb.js'
import { genreScore, explain, topGenres } from './taste.js'

const MAX_SEEDS = 4
const MIN_VOTES = 100

const CACHE_PREFIX = 'watchlist-recs:discover:'
const CACHE_TTL = 6 * 60 * 60 * 1000

const POOL_SIZE = 60

const mediaTypeOf = (item) => (item.type === 'movie' ? 'movie' : 'tv')
const appTypeOf = (mediaType) => (mediaType === 'movie' ? 'movie' : 'show')

const titleKey = (title, year) =>
  `${String(title ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '')}:${year ?? ''}`

function ownedIndex(items) {
  const ids = new Set()
  const titles = new Set()
  for (const i of items ?? []) {
    if (i.tmdbId) ids.add(`${mediaTypeOf(i)}:${i.tmdbId}`)
    titles.add(titleKey(i.title, i.year))
    titles.add(titleKey(i.title, ''))
  }
  return { ids, titles }
}

const isOwned = (owned, c) =>
  owned.ids.has(`${c.mediaType}:${c.tmdbId}`) ||
  owned.titles.has(titleKey(c.title, c.year ?? '')) ||
  owned.titles.has(titleKey(c.title, ''))

function toCandidate(raw, mediaType, maps) {
  const names = (raw.genre_ids ?? [])
    .map((id) => maps[mediaType]?.[id])
    .filter(Boolean)
  return {
    key: `${mediaType}:${raw.id}`,
    tmdbId: raw.id,
    mediaType,
    type: appTypeOf(mediaType),
    title: raw.title ?? raw.name ?? '',
    year: Number((raw.release_date ?? raw.first_air_date)?.slice(0, 4)) || null,
    posterPath: raw.poster_path ?? null,
    tmdbRating: raw.vote_average ? Math.round(raw.vote_average * 10) / 10 : null,
    voteCount: raw.vote_count ?? 0,
    overview: raw.overview ?? '',
    genres: names,
    score: 0,
    seeds: [],
    why: null,
  }
}

function cacheKey(seedItems, type) {
  const ids = seedItems.map((s) => `${mediaTypeOf(s.item)}${s.item.tmdbId}`).sort().join(',')
  return `${CACHE_PREFIX}${type}:${ids}`
}

function readCache(key) {
  try {
    const raw = JSON.parse(localStorage.getItem(key) || 'null')
    if (raw?.at && Date.now() - raw.at < CACHE_TTL) return raw.results
  } catch {
  }
  return null
}

function writeCache(key, results) {
  try {
    localStorage.setItem(key, JSON.stringify({ at: Date.now(), results }))
  } catch {
  }
}

export function clearDiscoverCache() {
  try {
    const stale = Object.keys(localStorage).filter((k) => k.startsWith(CACHE_PREFIX))
    for (const k of stale) localStorage.removeItem(k)
  } catch {
  }
}

export async function discover(items, { affinity, signals, type = 'all', limit = 12, offset = 0, force = false } = {}) {
  if (!hasKey()) throw new NoKeyError()

  const seedItems = signals
    .filter((s) => s.item.tmdbId && s.weight > 0)
    .filter((s) => type === 'all' || s.item.type === type)
    .slice(0, MAX_SEEDS)

  const seedTitles = seedItems.map((s) => s.item.title)
  const key = cacheKey(seedItems, type)

  const window = (pool, cached) => {
    const owned = ownedIndex(items)
    const avail = pool.filter((c) => !isOwned(owned, c))
    let results
    if (avail.length <= limit) {
      results = avail
    } else {
      const start = offset % avail.length
      results = Array.from({ length: limit }, (_, i) => avail[(start + i) % avail.length])
    }
    return { results, poolSize: avail.length, seeds: seedTitles, cached }
  }

  if (!force) {
    const cached = readCache(key)
    if (cached) return window(cached, true)
  }

  const maps = await genreMaps()
  const wanted = type === 'all' ? ['movie', 'tv'] : [type === 'movie' ? 'movie' : 'tv']

  const pool = new Map()

  const addRaw = (raw, mediaType, seedTitle, seedWeight) => {
    if (!raw?.id || !raw.poster_path) return
    if ((raw.vote_count ?? 0) < MIN_VOTES) return
    const k = `${mediaType}:${raw.id}`
    let c = pool.get(k)
    if (!c) {
      c = toCandidate(raw, mediaType, maps)
      pool.set(k, c)
    }
    if (seedTitle) {
      c.seeds.push({ title: seedTitle, weight: seedWeight })
    }
  }

  const seedResults = await Promise.allSettled(
    seedItems.map((s) => fetchSimilarTo(s.item.tmdbId, mediaTypeOf(s.item)))
  )
  seedResults.forEach((res, i) => {
    if (res.status !== 'fulfilled') return
    const seed = seedItems[i]
    const mediaType = mediaTypeOf(seed.item)
    if (!wanted.includes(mediaType)) return
    for (const raw of res.value) addRaw(raw, mediaType, seed.item.title, seed.weight)
  })

  const lead = topGenres(affinity, 3)
  if (lead.length) {
    const jobs = []
    for (const mediaType of wanted) {
      for (const page of [1, 2]) {
        jobs.push(
          (async () => {
            const idsByName = await genreIdsByName(mediaType)
            const ids = lead.map((g) => idsByName.get(g.name.toLowerCase())).filter(Boolean)
            return { mediaType, raws: await discoverByGenres(mediaType, ids, { page }) }
          })()
        )
      }
    }
    for (const res of await Promise.allSettled(jobs)) {
      if (res.status !== 'fulfilled') continue
      for (const raw of res.value.raws) addRaw(raw, res.value.mediaType, null, 0)
    }
  }

  const owned = ownedIndex(items)
  const results = []
  for (const c of pool.values()) {
    if (isOwned(owned, c)) continue

    const seedScore = c.seeds.reduce((sum, s) => sum + s.weight, 0)
    const fit = genreScore(c.genres, affinity)
    const quality = c.tmdbRating ? (c.tmdbRating - 6.5) * 0.12 : 0
    c.score = seedScore * 1.2 + fit + quality
    if (c.score <= 0) continue

    c.why = c.seeds.length
      ? { genres: [], because: [...new Set(c.seeds.map((s) => s.title))].slice(0, 2) }
      : explain(c.genres, affinity, signals)
    results.push(c)
  }

  results.sort((a, b) => b.score - a.score)
  const top = results.slice(0, POOL_SIZE)
  writeCache(key, top)
  return window(top, false)
}
