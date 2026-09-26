const API = 'https://kitsu.io/api/edge/anime'

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
