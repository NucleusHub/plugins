// Port of native/Sources/DiscoverModel.swift: Discover's rows, fetched from TMDb and ranked by taste.
// Kept for the session so switching tabs doesn't refetch; it reloads when old or when MovieDNA changed.
import { reactive } from 'vue'
import { Taste, GenreMap, MAX_SEEDS, blend, alternateKinds, parseList, trailerKey, keyOf } from './taste.js'

const MAX_AGE = 30 * 60 * 1000
const MIN_VOTES = 100

const emptyFeed = () => ({ picks: [], trailers: [], following: [], newReleases: [], trending: [], different: [] })
const isEmpty = (f) => !(f.picks.length || f.following.length || f.newReleases.length || f.trending.length || f.different.length)

export const state = reactive({ feed: emptyFeed(), loading: false, failed: false, usesDNA: true })
let loadedAt = 0
let fingerprintOf = ''
let genreMap = null

// What the feed depends on; Interested presses and strength edits beyond rounding change it.
export function fingerprint(dna) {
  if (!dna.enabled) return 'off'
  const genres = dna.genres.slice(0, 5).map((g) => `${g.name}${Math.trunc(g.strength / 20)}`)
  const titles = dna.titles.slice(0, MAX_SEEDS).map((t) => t.tmdbID)
  const people = dna.people.filter((p) => p.followed).map((p) => p.personID)
  return [...genres, '|', ...titles, '|', ...people].join(',')
}

// Drops a title from every row at once, after the person said no.
export function remove(id) {
  const f = state.feed
  f.picks = f.picks.filter((s) => s.id !== id)
  f.trailers = f.trailers.filter((t) => t.title.id !== id)
  for (const row of ['following', 'newReleases', 'trending', 'different']) f[row] = f[row].filter((s) => s.id !== id)
}

// Loads unless what's there is fresh and was built from the same taste.
export async function refresh(host, force = false) {
  const dna = host.movieDNA
  const print = fingerprint(dna)
  if (!force && !state.loading && loadedAt && Date.now() - loadedAt < MAX_AGE && print === fingerprintOf && !isEmpty(state.feed)) return
  if (!host.hasTMDbKey || state.loading) return
  state.loading = true
  const taste = dna.enabled ? Taste.fromDNA(dna, host.library) : Taste.fromLibrary(host.library, dna.notInterested)
  try {
    const genres = await loadGenres(host)
    state.feed = await build(host, taste, genres)
    state.usesDNA = dna.enabled
    state.failed = false
    loadedAt = Date.now()
    fingerprintOf = print
  } catch {
    state.failed = isEmpty(state.feed)
  } finally {
    state.loading = false
  }
  // MovieDNA changed while this load ran.
  if (fingerprint(host.movieDNA) !== print) refresh(host)
}

async function loadGenres(host) {
  if (genreMap) return genreMap
  const [movie, tv] = await Promise.all([host.tmdb('/genre/movie/list'), host.tmdb('/genre/tv/list')])
  genreMap = new GenreMap({ movie: GenreMap.parse(movie), show: GenreMap.parse(tv) })
  return genreMap
}

// Every list fetched side by side, in order; a list that fails comes back empty.
const fetchLists = (requests, host, genres) =>
  Promise.all(requests.map((r) => host.tmdb(r.path, r.query ?? {}).then((json) => parseList(json, r.kind, genres, r.reason), () => [])))

async function trailersFor(titles, host) {
  const found = await Promise.all(titles.map(async (title) => {
    const path = `/${title.kind === 'movie' ? 'movie' : 'tv'}/${title.tmdbID}/videos`
    const key = await host.tmdb(path, { include_video_language: 'en,null' }).then(trailerKey, () => null)
    return key ? { key, title } : null
  }))
  return found.filter(Boolean).slice(0, 6)
}

// What people they follow made lately or are making now.
async function followingRow(taste, host) {
  if (!taste.fromDNA) return []
  const people = taste.followed.slice(0, 8)
  const found = await Promise.all(people.map((p) => host.person(p.personID).catch(() => null)))
  const cutoff = new Date(new Date().setFullYear(new Date().getFullYear() - 2)).toISOString().slice(0, 10)
  const seen = new Set()
  const out = []
  people.forEach((person, i) => {
    const recent = (found[i]?.credits ?? [])
      .filter((c) => (c.date ?? '9999') >= cutoff && !c.isSelf && c.posterURL)
      .sort((a, b) => (b.date ?? '9999').localeCompare(a.date ?? '9999'))
    for (const c of recent.slice(0, 4)) {
      const id = keyOf(c.kind, c.titleID)
      if (seen.has(id)) continue
      seen.add(id)
      out.push({
        id, kind: c.kind, tmdbID: c.titleID, title: c.title, date: c.date, posterURL: c.posterURL,
        genres: [], voteAverage: 0, voteCount: c.voteCount, reason: { type: 'following', name: person.name }, score: 0,
      })
    }
  })
  return out
}

async function build(host, taste, genres) {
  const fresh = (s) => !taste.excluded.has(s.id)
  const ranked = (list, seedWeight = 0) =>
    list
      .filter((s) => fresh(s) && s.voteCount >= MIN_VOTES && !taste.isUnwantedAnimation(s))
      .map((s) => ({ ...s, score: taste.score(s, seedWeight) }))
      .filter((s) => s.score > -0.1)
      .sort((a, b) => b.score - a.score)

  // Picks: one list per seed title and per top genre, each ranked, then taken in turns.
  const picks = taste.seeds.map((s) => ({
    path: `/${s.kind === 'movie' ? 'movie' : 'tv'}/${s.tmdbID}/recommendations`, kind: s.kind, reason: { type: 'because', title: s.title },
  }))
  const skip = taste.wantsAnimation ? {} : { without_genres: '16' }
  for (const name of taste.topGenres()) {
    for (const kind of ['movie', 'show']) {
      const id = genres.id(name, kind)
      if (!id) continue
      picks.push({
        path: kind === 'movie' ? '/discover/movie' : '/discover/tv',
        query: { with_genres: String(id), sort_by: 'popularity.desc', 'vote_count.gte': '200', ...skip },
        kind, reason: { type: 'genres', names: [] },
      })
    }
  }
  const current = [
    { path: '/movie/now_playing', kind: 'movie', reason: { type: 'newRelease' } },
    { path: '/tv/on_the_air', kind: 'show', reason: { type: 'newRelease' } },
    { path: '/trending/all/week', kind: null, reason: { type: 'trending' } },
  ]
  // Outside the comfort zone: highly rated titles from genres the person hasn't touched.
  let different = []
  if (taste.fromDNA) {
    const day = Math.floor(Date.now() / 86400000)
    different = taste.unexplored(Object.values(genres.names.movie), day).flatMap((name) => {
      const id = genres.id(name, 'movie')
      return id ? [{
        path: '/discover/movie',
        query: { with_genres: String(id), sort_by: 'vote_average.desc', 'vote_count.gte': '800', 'vote_average.gte': '7.3' },
        kind: 'movie', reason: { type: 'different', genre: name },
      }] : []
    })
  }

  const [followed, lists] = await Promise.all([followingRow(taste, host), fetchLists([...picks, ...current, ...different], host, genres)])
  const pickLists = lists.slice(0, picks.length)
  const [newMovies, newShows, trendingAll] = lists.slice(picks.length, picks.length + current.length)
  const differentLists = lists.slice(picks.length + current.length)

  const feed = emptyFeed()
  const seeds = taste.seeds.length
  feed.picks = blend(
    pickLists.map((list, i) =>
      i < seeds
        ? ranked(list, taste.seeds[i].weight)
        : ranked(list.map((s) => ({ ...s, reason: { type: 'genres', names: taste.liked(s.genres) } })))
    ),
    20
  )
  feed.trailers = await trailersFor(feed.picks.slice(0, 8), host)
  feed.following = followed.filter(fresh)

  // New and trending, ranked by taste but still new and trending first.
  const releases = [...newMovies, ...newShows].filter((s) => fresh(s) && !taste.isUnwantedAnimation(s))
  const byFit = releases
    .map((s, i) => ({ s, rank: taste.fit(s.genres) - i * 0.01 }))
    .sort((a, b) => b.rank - a.rank)
    .map((x) => x.s)
  feed.newReleases = alternateKinds(byFit.slice(0, 20))
  // Trending stays what's trending; unwanted animation just goes last.
  const trending = trendingAll.filter(fresh)
  feed.trending = [...trending.filter((s) => !taste.isUnwantedAnimation(s)), ...trending.filter((s) => taste.isUnwantedAnimation(s))].slice(0, 20)

  for (const list of differentLists) {
    feed.different.push(...list.filter((s) => fresh(s) && !feed.different.some((d) => d.id === s.id)).slice(0, 8))
  }
  return feed
}
