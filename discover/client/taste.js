// Port of native/Sources/Taste.swift and Suggestion.swift. Pure; the host's MovieDNA and library go in.

export const MAX_SEEDS = 5
// A genre the person never showed interest in isn't the same as one they want.
const UNKNOWN_GENRE = -0.15

export const keyOf = (kind, tmdbID) => `${kind}:${tmdbID}`
const lower = (s) => s.toLowerCase()
const owned = (library) => new Set(library.filter((t) => t.tmdbID).map((t) => keyOf(t.kind, t.tmdbID)))

export class Taste {
  constructor() {
    // Lowercased genre name -> -1 (avoid) … 1 (love).
    this.genres = {}
    // Lowercased -> the name as TMDb writes it.
    this.genreNames = {}
    this.seeds = []
    this.followed = []
    // `movie:603` keys never to suggest: already in the library, or turned down.
    this.excluded = new Set()
    this.fromDNA = false
  }

  static fromDNA(dna, library) {
    const t = new Taste()
    t.fromDNA = true
    for (const g of dna.genres) {
      t.genres[lower(g.name)] = g.strength / 100
      t.genreNames[lower(g.name)] = g.name
    }
    const strong = dna.titles
      .filter((x) => x.strength >= 30)
      .slice(0, MAX_SEEDS * 3)
      .map((x) => ({ kind: x.kind, tmdbID: x.tmdbID, title: x.name, weight: x.strength / 100 }))
    const genresByTitle = new Map()
    for (const x of library) if (x.tmdbID && !genresByTitle.has(keyOf(x.kind, x.tmdbID))) genresByTitle.set(keyOf(x.kind, x.tmdbID), x.genres)
    t.seeds = diverseSeeds(strong, (s) => genresByTitle.get(keyOf(s.kind, s.tmdbID)) ?? [], MAX_SEEDS)
    t.followed = dna.people.filter((p) => p.followed)
    t.excluded = new Set([...dna.notInterested, ...owned(library)])
    return t
  }

  // MovieDNA off: finished titles, weighted by rating, favorites and how recently they were watched.
  static fromLibrary(library, notInterested, now = Date.now()) {
    const t = new Taste()
    const finished = library
      .filter((x) => x.isCompleted)
      .sort((a, b) => (b.finishedAt?.getTime() ?? 0) - (a.finishedAt?.getTime() ?? 0))
      .slice(0, 60)
    const raw = {}
    for (const title of finished) {
      const days = Math.max(0, (now - (title.finishedAt?.getTime() ?? now)) / 86400000)
      const recency = 0.5 ** (days / 60)
      let quality = title.rating != null ? (title.rating - 5.5) / 2.5 : 1
      quality = Math.min(2, Math.max(-1.5, quality)) + (title.favorite ? 0.5 : 0)
      const weight = recency * quality
      if (title.tmdbID && weight > 0 && t.seeds.length < 4) {
        t.seeds.push({ kind: title.kind, tmdbID: title.tmdbID, title: title.title, weight: Math.min(1, weight) })
      }
      if (!title.genres.length) continue
      const share = weight / Math.sqrt(title.genres.length)
      for (const g of title.genres) {
        raw[lower(g)] = (raw[lower(g)] ?? 0) + share
        t.genreNames[lower(g)] ??= g
      }
    }
    const top = Math.max(0, ...Object.values(raw).map(Math.abs))
    if (top > 0) for (const [k, v] of Object.entries(raw)) t.genres[k] = v / top
    t.excluded = new Set([...notInterested, ...owned(library)])
    return t
  }

  // About -1 … 1; titles with many genres don't win just by having more.
  fit(genreNames) {
    if (!genreNames.length || !Object.keys(this.genres).length) return 0
    const sum = genreNames.reduce((acc, g) => acc + (this.genres[lower(g)] ?? UNKNOWN_GENRE), 0)
    return sum / Math.sqrt(genreNames.length)
  }

  // TMDb's popular action, sci-fi and fantasy TV is mostly anime, so animation only comes in when it's liked.
  get wantsAnimation() { return (this.genres.animation ?? 0) >= 0.2 }

  isUnwantedAnimation(s) {
    return !this.wantsAnimation && s.genres.some((g) => lower(g) === 'animation')
  }

  topGenres(n = 4) {
    return Object.entries(this.genres)
      .filter(([, v]) => v > 0.05)
      .sort((a, b) => b[1] - a[1])
      .slice(0, n)
      .map(([k]) => this.genreNames[k])
      .filter(Boolean)
  }

  liked(genreNames, limit = 2) {
    return genreNames
      .filter((g) => (this.genres[lower(g)] ?? 0) > 0.15)
      .sort((a, b) => (this.genres[lower(b)] ?? 0) - (this.genres[lower(a)] ?? 0))
      .slice(0, limit)
  }

  // Genres never touched and not disliked: where "outside your comfort zone" looks. A different set each day.
  unexplored(all, day, limit = 2) {
    const candidates = all.filter((name) => {
      const w = this.genres[lower(name)]
      return w === undefined || Math.abs(w) < 0.1
    }).sort()
    if (!candidates.length) return []
    const start = day % candidates.length
    return Array.from({ length: Math.min(limit, candidates.length) }, (_, i) => candidates[(start + i) % candidates.length])
  }

  // How well it fits, how strongly it was recommended, and how good TMDb thinks it is.
  score(s, seedWeight = 0) {
    const quality = s.voteAverage > 0 ? (s.voteAverage - 6.5) * 0.12 : 0
    return seedWeight * 1.2 + this.fit(s.genres) + quality
  }
}

// Takes the sources in turns so no single recommendation or genre fills the row, keeps any one main genre
// to about a third, and alternates movies and shows.
export function blend(buckets, limit, maxShare = 0.34) {
  const queues = buckets.map((b) => [...b])
  const out = []
  const seen = new Set()
  const genreCount = {}
  const deferred = []
  const cap = Math.max(2, Math.round(limit * maxShare))
  while (out.length < limit && queues.some((q) => q.length)) {
    for (const q of queues) {
      if (out.length >= limit) break
      const next = q.shift()
      if (!next || seen.has(next.id)) continue
      seen.add(next.id)
      const main = next.genres[0] ? lower(next.genres[0]) : ''
      if (main && (genreCount[main] ?? 0) >= cap) {
        deferred.push(next)
        continue
      }
      genreCount[main] = (genreCount[main] ?? 0) + 1
      out.push(next)
    }
  }
  // Only when nothing else is left does a genre go over its share.
  out.push(...deferred.slice(0, Math.max(0, limit - out.length)))
  return alternateKinds(out)
}

export function alternateKinds(list) {
  const movies = list.filter((s) => s.kind === 'movie')
  const shows = list.filter((s) => s.kind === 'show')
  const out = []
  let movieTurn = list[0]?.kind !== 'show'
  while (movies.length || shows.length) {
    if (movieTurn && movies.length) out.push(movies.shift())
    else if (shows.length) out.push(shows.shift())
    else out.push(movies.shift())
    movieTurn = !movieTurn
  }
  return out
}

// The seeds, spread over genres: each next one is the strongest that adds the least overlap.
export function diverseSeeds(candidates, genresOf, limit) {
  const pool = [...candidates]
  const picked = []
  const covered = new Set()
  const value = (s) => {
    const g = new Set(genresOf(s).map(lower))
    const overlap = g.size ? [...g].filter((x) => covered.has(x)).length / g.size : 0
    return s.weight * (1 - 0.6 * overlap)
  }
  while (picked.length < limit && pool.length) {
    let best = 0
    for (let i = 1; i < pool.length; i++) if (value(pool[i]) > value(pool[best])) best = i
    const [seed] = pool.splice(best, 1)
    picked.push(seed)
    for (const g of genresOf(seed)) covered.add(lower(g))
  }
  return picked
}

// TMDb's genre ids and names, both ways.
export class GenreMap {
  constructor(names = { movie: {}, show: {} }) { this.names = names }
  name(id, kind) { return this.names[kind]?.[id] ?? null }
  id(name, kind) {
    const hit = Object.entries(this.names[kind] ?? {}).find(([, n]) => lower(n) === lower(name))
    return hit ? Number(hit[0]) : null
  }
  static parse(json) {
    return Object.fromEntries((json?.genres ?? []).map((g) => [g.id, g.name]))
  }
}

// TMDb's paged list shape, keeping titles with a poster. `kind` is for single-type endpoints;
// mixed lists say it per result in `media_type`.
export function parseList(json, kind, genres, reason) {
  return (json?.results ?? []).flatMap((r) => {
    const type = r.media_type === 'tv' ? 'show' : r.media_type === 'movie' ? 'movie' : kind
    const title = r.title || r.name
    if (!type || !r.id || !r.poster_path || !title) return []
    return [{
      id: keyOf(type, r.id),
      kind: type,
      tmdbID: r.id,
      title,
      date: r.release_date || r.first_air_date || null,
      posterURL: `https://image.tmdb.org/t/p/w342${r.poster_path}`,
      genres: (r.genre_ids ?? []).map((id) => genres.name(id, type)).filter(Boolean),
      voteAverage: r.vote_average ?? 0,
      voteCount: r.vote_count ?? 0,
      reason,
      score: 0,
    }]
  })
}

// The first YouTube trailer of a `/videos` response, official ones first.
export function trailerKey(json) {
  const youtube = (json?.results ?? []).filter((v) => v.site === 'YouTube' && v.key)
  const trailers = youtube.filter((v) => v.type === 'Trailer')
  return (trailers.find((v) => v.official) ?? trailers[0] ?? youtube.find((v) => v.type === 'Teaser'))?.key ?? null
}
