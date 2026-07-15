// Anime search source for Watchlist, powered by Kitsu's public JSON:API
// (https://kitsu.docs.apiary.io) — free, no API key, and browser-friendly
// (CORS-open), so it runs entirely client-side alongside Watchlist's built-in
// TMDb source. Contributed by the `anime-source` plugin.
//
// Implements Watchlist's client search-source contract (see
// apps/watchlist/client/src/api/sources.js):
//   search(query) -> normalized results [{ key, title, subtitle, poster, type }]
//   toForm(result) -> partial form fields merged into the add/edit form
//
// Self-contained on purpose: no host imports (uses only the browser `fetch`), so
// the plugin bundles cleanly wherever Watchlist globs it. One request returns
// everything both search and toForm need, so selecting a result costs no second
// round-trip.
const API = 'https://kitsu.io/api/edge/anime'

// Kitsu `subtype` (TV, movie, OVA, ONA, special, music) → Watchlist's two kinds.
// Only films are "movie"; everything episodic is a "show".
const typeOf = (a) => (a.subtype === 'movie' ? 'movie' : 'show')
const titleOf = (a) =>
  a.canonicalTitle || a.titles?.en || a.titles?.en_jp || a.titles?.ja_jp || ''
const yearOf = (a) => (a.startDate ? a.startDate.slice(0, 4) : '')

const SUBTYPE_LABEL = {
  TV: 'TV', movie: 'Movie', OVA: 'OVA', ONA: 'ONA', special: 'Special', music: 'Music',
}

async function query(q) {
  const url = `${API}?filter[text]=${encodeURIComponent(q)}&page[limit]=10`
  const res = await fetch(url, { headers: { Accept: 'application/vnd.api+json' } })
  if (!res.ok) throw new Error(`Kitsu ${res.status}`)
  const json = await res.json()
  return json?.data || []
}

export default {
  id: 'kitsu-anime',
  label: 'Anime (Kitsu)',

  async search(q) {
    const data = await query(q)
    return data.map((entry) => {
      const a = entry.attributes || {}
      const year = yearOf(a)
      return {
        key: `kitsu:${entry.id}`,
        title: titleOf(a),
        subtitle: [year, SUBTYPE_LABEL[a.subtype] || ''].filter(Boolean).join(' · '),
        poster: a.posterImage?.small || a.posterImage?.medium || a.posterImage?.tiny || null,
        type: typeOf(a),
        _raw: a,
      }
    })
  },

  // Everything is already in the search payload — map it into the form. Mirrors
  // the built-in TMDb source: title/type/year/poster always; runtime for films;
  // seasons/episodes/per-season progress for series (Kitsu lists anime as a
  // single run of N episodes, so seed one season for progress tracking).
  toForm(result) {
    const a = result._raw
    const type = typeOf(a)
    const year = yearOf(a)
    const form = {
      title: titleOf(a),
      type,
      year: year || '',
      posterUrl: a.posterImage?.original || a.posterImage?.large || a.posterImage?.medium || null,
    }
    const perEp = Number(a.episodeLength) || 0
    if (type === 'movie') {
      if (perEp) form.runtime = perEp
    } else {
      const eps = Number(a.episodeCount) || null
      form.seasons = 1
      form.episodes = eps
      if (eps && perEp) form.showRuntime = eps * perEp
      if (eps) {
        form.seasonProgress = [
          { seasonNumber: 1, name: 'Season 1', episodeCount: eps, watched: 0 },
        ]
      }
    }
    return form
  },
}
