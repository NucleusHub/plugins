// The "New to you" half — titles you don't have yet, found on TMDb and ranked
// against the same taste profile that orders your backlog (see taste.js).
//
// Two candidate sources, in priority order:
//   1. /recommendations on each recent finished title. TMDb builds these from
//      what people actually watch together, so they beat anything derivable
//      from genre overlap alone.
//   2. /discover filtered to your strongest genres, as backfill — needed when
//      you have few seeds, or when everything the seeds suggest is already on
//      your list.
//
// The result is cached per (seed set × type) for a few hours: the inputs only
// move when you finish something, so re-deriving it on every visit would spend
// requests to produce the identical list.

import { fetchSimilarTo, discoverByGenres, genreMaps, genreIdsByName, hasKey, NoKeyError } from './tmdb.js'
import { genreScore, explain, topGenres } from './taste.js'

// How many finished titles we ask TMDb about. Each is one request; past the
// fourth the recency weight is small enough that its suggestions rarely win a
// slot anyway.
const MAX_SEEDS = 4
// Floor on TMDb vote count. Below this the rating is noise — a 9.4 from eleven
// people is not a recommendation.
const MIN_VOTES = 100

const CACHE_PREFIX = 'watchlist-recs:discover:'
const CACHE_TTL = 6 * 60 * 60 * 1000

// How many scored candidates we keep. Far more than one screenful on purpose:
// "show me different ones" pages through this pool client-side, so it's instant
// and actually different — re-querying TMDb would spend requests to rebuild the
// identical ranking and hand back the identical head of it.
const POOL_SIZE = 60

const mediaTypeOf = (item) => (item.type === 'movie' ? 'movie' : 'tv')
const appTypeOf = (mediaType) => (mediaType === 'movie' ? 'movie' : 'show')

// Loose title key for the "do I already have this?" test, used only for items
// that carry no tmdbId (added by hand, or from a non-TMDb source). Punctuation
// and case vary between sources; the year does the disambiguating.
const titleKey = (title, year) =>
  `${String(title ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '')}:${year ?? ''}`

// Everything already in the library, in both forms the filter needs. Items are
// excluded whatever their status — a suggestion you already finished is worse
// than useless, and one sitting in your backlog belongs in the other section.
function ownedIndex(items) {
  const ids = new Set()
  const titles = new Set()
  for (const i of items ?? []) {
    if (i.tmdbId) ids.add(`${mediaTypeOf(i)}:${i.tmdbId}`)
    titles.add(titleKey(i.title, i.year))
    // A title match with no year still counts — better a rare false positive
    // (hiding one suggestion) than showing someone their own library back.
    titles.add(titleKey(i.title, ''))
  }
  return { ids, titles }
}

const isOwned = (owned, c) =>
  owned.ids.has(`${c.mediaType}:${c.tmdbId}`) ||
  owned.titles.has(titleKey(c.title, c.year ?? '')) ||
  owned.titles.has(titleKey(c.title, ''))

// One TMDb list entry → the shape the surface renders and the add button posts.
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
    // Filled in during scoring.
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
    // treat an unreadable cache as a miss
  }
  return null
}

function writeCache(key, results) {
  try {
    localStorage.setItem(key, JSON.stringify({ at: Date.now(), results }))
  } catch {
    // storage full or blocked — we just re-fetch next time
  }
}

// Drop every cached discovery result. Called by the surface's refresh button,
// which exists precisely for "I don't like these, try again".
export function clearDiscoverCache() {
  try {
    const stale = Object.keys(localStorage).filter((k) => k.startsWith(CACHE_PREFIX))
    for (const k of stale) localStorage.removeItem(k)
  } catch {
    // nothing to clear if storage is unavailable
  }
}

// Titles you don't have, best first.
//
// `type` is 'all' | 'movie' | 'show'. Throws NoKeyError when the app has no
// TMDb key configured — the caller renders that as an explained gap rather than
// a failure, since the backlog half is unaffected.
export async function discover(items, { affinity, signals, type = 'all', limit = 12, offset = 0, force = false } = {}) {
  if (!hasKey()) throw new NoKeyError()

  // Seeds: recent finished titles you didn't dislike, that we can look up.
  const seedItems = signals
    .filter((s) => s.item.tmdbId && s.weight > 0)
    .filter((s) => type === 'all' || s.item.type === type)
    .slice(0, MAX_SEEDS)

  const seedTitles = seedItems.map((s) => s.item.title)
  const key = cacheKey(seedItems, type)

  // Slice one window out of the scored pool. Re-applies the ownership filter on
  // the way out, not just on the way in: adding a suggestion doesn't change the
  // seed set, so the cache stays valid — but the title you just added must drop
  // off. `poolSize` is what tells the caller whether paging further is possible.
  const window = (pool, cached) => {
    const owned = ownedIndex(items)
    const avail = pool.filter((c) => !isOwned(owned, c))
    // Wrap the window around the pool rather than running off the end, so the
    // last page is a full row of cards instead of a stray two. Everything in
    // the pool is a ranked suggestion, so a window straddling the wrap point is
    // no less valid than one that doesn't.
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

  // ── Candidate gathering ────────────────────────────────────────────────────
  const pool = new Map() // key → candidate

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

  // 1. "More like this" per seed. One seed's outage shouldn't lose the others.
  const seedResults = await Promise.allSettled(
    seedItems.map((s) => fetchSimilarTo(s.item.tmdbId, mediaTypeOf(s.item)))
  )
  seedResults.forEach((res, i) => {
    if (res.status !== 'fulfilled') return
    const seed = seedItems[i]
    // /movie/{id}/recommendations returns only movies and /tv/{id}/… only
    // shows, so the seed's own media type is the results' type — no need to
    // sniff `media_type`, which these endpoints don't always set.
    const mediaType = mediaTypeOf(seed.item)
    if (!wanted.includes(mediaType)) return
    for (const raw of res.value) addRaw(raw, mediaType, seed.item.title, seed.weight)
  })

  // 2. Genre backfill. Always run it — it's what keeps the list from being four
  //    seeds' worth of the same franchise, and it's the only source at all for
  //    someone whose finished items have no TMDb ids. Two pages deep, because
  //    one page per media type barely covers a single screenful once your own
  //    library is filtered out, and the pool is what "show different ones"
  //    pages through.
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

  // ── Scoring ────────────────────────────────────────────────────────────────
  const owned = ownedIndex(items)
  const results = []
  for (const c of pool.values()) {
    if (isOwned(owned, c)) continue

    // Being suggested by several of your recent watches is the strongest thing
    // a candidate can have going for it, so it's weighted well above genre fit.
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
