const API = 'https://graphql.anilist.co'
const UA = 'Nucleus-Shelf-MangaSource/1.0'

const SEARCH_QUERY = `query ($q: String) {
  Page(perPage: 25) {
    media(search: $q, type: MANGA, sort: SEARCH_MATCH) {
      id
      title { romaji english native }
      description(asHtml: false)
      genres
      chapters
      volumes
      countryOfOrigin
      startDate { year }
      siteUrl
      coverImage { large extraLarge }
      staff(perPage: 8, sort: RELEVANCE) { edges { role node { name { full } } } }
    }
  }
}`

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function stripHtml(s) {
  return String(s || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

const LANG_BY_COUNTRY = { JP: 'ja', KR: 'ko', CN: 'zh', TW: 'zh' }

export default class MangaProvider {
  id = 'manga'
  label = 'Manga (AniList)'
  requiresKey = false

  available() { return true }

  async search(query) {
    const q = String(query || '').trim()
    if (q.length < 2) return []

    let res
    for (let attempt = 0; attempt < 2; attempt++) {
      res = await fetch(API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': UA },
        body: JSON.stringify({ query: SEARCH_QUERY, variables: { q } }),
      })
      if (res.status !== 429) break
      await sleep((Number(res.headers.get('retry-after')) || 1) * 1000 + 100)
    }
    if (!res.ok) {
      console.warn(`[manga-source] AniList search "${q}" → HTTP ${res.status}`)
      return []
    }
    const json = await res.json()
    const media = json?.data?.Page?.media || []
    const results = media.map((m) => this._fromMedia(m))
    console.log(`[manga-source] AniList search "${q}" → ${results.length} result(s)`)
    return results
  }

  async getByIsbn() { return null }

  _empty() {
    return {
      title: '', subtitle: '', description: '', authors: [], series: null,
      genres: [], language: '', publisher: '', publishedDate: '',
      pageCount: null, coverUrl: null, isbn: '', identifiers: {}, source: this.id,
    }
  }

  _fromMedia(m) {
    const romaji = m.title?.romaji || ''
    const english = m.title?.english || ''
    const native = m.title?.native || ''
    const title = english || romaji || native || ''
    const subtitle = [romaji, native].find((t) => t && t !== title) || ''

    const authors = []
    for (const e of m.staff?.edges || []) {
      if (!/story|art/i.test(e.role || '')) continue
      const name = e.node?.name?.full
      if (name && !authors.includes(name)) authors.push(name)
    }

    return {
      ...this._empty(),
      title,
      subtitle,
      description: stripHtml(m.description),
      authors,
      genres: (m.genres || []).slice(0, 5),
      language: LANG_BY_COUNTRY[m.countryOfOrigin] || '',
      publishedDate: m.startDate?.year ? String(m.startDate.year) : '',
      coverUrl: m.coverImage?.extraLarge || m.coverImage?.large || null,
      identifiers: {
        anilist: m.id,
        anilistUrl: m.siteUrl,
        chapters: m.chapters ?? null,
        volumes: m.volumes ?? null,
      },
      source: this.id,
    }
  }
}
