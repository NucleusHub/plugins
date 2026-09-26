const HALF_LIFE_DAYS = 60
const DAY = 24 * 60 * 60 * 1000

const MAX_SIGNALS = 60

export const watchedAt = (item) => new Date(item.completedAt ?? item.updatedAt ?? item.dateAdded ?? 0)

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

export function genreAffinity(signalList) {
  const raw = new Map()
  for (const s of signalList) {
    const genres = s.item.genres ?? []
    if (!genres.length) continue
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

const LEAD_THRESHOLD = 0.05

export function topGenres(affinity, n = 5) {
  return [...affinity.values()]
    .filter((g) => g.score > LEAD_THRESHOLD)
    .sort((a, b) => b.score - a.score)
    .slice(0, n)
}

export function genreScore(genres, affinity) {
  const list = genres ?? []
  if (!list.length || !affinity.size) return 0
  let sum = 0
  for (const g of list) sum += affinity.get(g.toLowerCase())?.score ?? 0
  return sum / Math.sqrt(list.length)
}

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

function bonuses(item) {
  let b = 0
  if (item.tmdbRating) b += (item.tmdbRating - 6) * 0.06
  if (item.favorite) b += 0.4
  if (item.watchLink) b += 0.05
  return b
}

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
