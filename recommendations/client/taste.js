// The taste profile — the part of this plugin that decides what "based on what
// you watched recently" actually means. Pure functions over the watchlist array
// the host hands the surface: no network, no storage, no Vue. That's what makes
// the local half of the recommendations work when TMDb is unreachable or the
// app has no API key configured.
//
// The model is deliberately small and legible, because a recommendation the
// user can't understand reads as noise. Every suggestion can name the genres
// and the finished titles that produced it (see `explain`).

// How fast a finished title stops counting. 60 days ≈ "the last couple of
// months dominate, last year still nudges". Recency is the whole point of the
// feature — a profile averaged over five years of viewing is just a list of the
// genres you own most of.
const HALF_LIFE_DAYS = 60
const DAY = 24 * 60 * 60 * 1000

// How many finished titles feed the profile at all. Past this, the recency
// weight has decayed to near-nothing anyway; the cap keeps a 2000-item library
// from being scored in full on every render.
const MAX_SIGNALS = 60

// When you finished something. `completedAt` is stamped by the server on the
// status transition; items completed before that field existed fall back to
// `updatedAt`, which is roughly right for them and never null.
export const watchedAt = (item) => new Date(item.completedAt ?? item.updatedAt ?? item.dateAdded ?? 0)

// Your rating, as a signed multiplier. An unrated item counts as a mild
// positive (you finished it, after all); a 9/10 counts for about twice that;
// anything below ~5.5 actively pushes its genres *down*, because "I sat through
// it and hated it" is a stronger signal than silence.
function qualityWeight(item) {
  let q = item.rating == null ? 1 : (item.rating - 5.5) / 2.5
  q = Math.max(-1.5, Math.min(2, q))
  if (item.favorite) q += 0.5
  return q
}

function recencyWeight(item, now) {
  const ageDays = Math.max(0, (now - watchedAt(item)) / DAY)
  return 0.5 ** (ageDays / HALF_LIFE_DAYS)
}

// The finished titles that feed the profile, most recent first, each with the
// weight it carries. Items with no genres still appear here — they're useless
// for genre affinity but they're perfectly good TMDb seeds.
export function signals(items, now = Date.now()) {
  return (items ?? [])
    .filter((i) => i.status === 'completed')
    .sort((a, b) => watchedAt(b) - watchedAt(a))
    .slice(0, MAX_SIGNALS)
    .map((item) => {
      const recency = recencyWeight(item, now)
      const quality = qualityWeight(item)
      return { item, recency, quality, weight: recency * quality }
    })
}

// Genre → affinity in roughly [-1, 1]. Positive means "more of this", negative
// means "you finished these and didn't like them". Normalized by the largest
// magnitude so the scale doesn't depend on library size.
export function genreAffinity(signalList) {
  const raw = new Map()
  for (const s of signalList) {
    const genres = s.item.genres ?? []
    if (!genres.length) continue
    // Split each title's weight across its genres, so a six-genre epic doesn't
    // outvote a tightly-tagged one just by carrying more labels.
    const share = s.weight / Math.sqrt(genres.length)
    for (const g of genres) {
      const key = g.toLowerCase()
      const entry = raw.get(key) ?? { name: g, score: 0 }
      entry.score += share
      raw.set(key, entry)
    }
  }
  let max = 0
  for (const { score } of raw.values()) max = Math.max(max, Math.abs(score))
  if (!max) return new Map()
  const out = new Map()
  for (const [key, { name, score }] of raw) out.set(key, { name, score: score / max })
  return out
}

// The genres to lead with, strongest first — used for the "your taste right
// now" summary and to seed TMDb's /discover. The floor matters: a genre whose
// only support is something you finished two years ago scores a rounding error
// above zero, and letting that steer a discovery query is worse than having one
// fewer genre in the mix.
const LEAD_THRESHOLD = 0.05

export function topGenres(affinity, n = 5) {
  return [...affinity.values()]
    .filter((g) => g.score > LEAD_THRESHOLD)
    .sort((a, b) => b.score - a.score)
    .slice(0, n)
}

// How well one title's genres match the profile. Same sqrt normalization as
// above, so breadth doesn't substitute for fit.
export function genreScore(genres, affinity) {
  const list = genres ?? []
  if (!list.length || !affinity.size) return 0
  let sum = 0
  for (const g of list) sum += affinity.get(g.toLowerCase())?.score ?? 0
  return sum / Math.sqrt(list.length)
}

// Why a title surfaced: which of its genres you're currently into, and the
// finished titles that put them there. This is what turns a ranked list into
// something a person can agree or disagree with.
export function explain(genres, affinity, signalList) {
  const matched = (genres ?? [])
    .map((g) => affinity.get(g.toLowerCase()))
    .filter((g) => g && g.score > 0.15)
    .sort((a, b) => b.score - a.score)
    .slice(0, 2)
  if (!matched.length) return null

  const names = new Set(matched.map((g) => g.name.toLowerCase()))
  const because = signalList
    .filter((s) => s.weight > 0 && (s.item.genres ?? []).some((g) => names.has(g.toLowerCase())))
    .slice(0, 2)
    .map((s) => s.item.title)

  return { genres: matched.map((g) => g.name), because }
}

// ── Ranking your own backlog ─────────────────────────────────────────────────

// Nudges that stop the list being pure genre-matching: a well-regarded title
// beats a poorly-regarded one at the same fit, and something you already
// flagged as wanted beats something you added and forgot.
function bonuses(item) {
  let b = 0
  if (item.tmdbRating) b += (item.tmdbRating - 6) * 0.06
  if (item.favorite) b += 0.4
  if (item.watchLink) b += 0.05 // you can actually start it tonight
  return b
}

// Your unwatched items, best match first. `type` is 'all' | 'movie' | 'show'.
//
// When the profile is empty — a fresh library, or one whose items predate genre
// tags — this still returns something useful (ranked by the nudges alone)
// rather than an arbitrary order, and `hasProfile` tells the UI to explain why
// the picks look generic.
export function rankBacklog(items, { affinity, signals: signalList, type = 'all', limit = 12 }) {
  const hasProfile = affinity.size > 0
  const ranked = (items ?? [])
    .filter((i) => i.status === 'planned' && (type === 'all' || i.type === type))
    .map((item) => {
      const fit = genreScore(item.genres, affinity)
      return { item, score: fit + bonuses(item), fit, why: explain(item.genres, affinity, signalList) }
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, limit)
  return { hasProfile, results: ranked }
}
