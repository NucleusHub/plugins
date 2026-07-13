// Manga import source for Shelf, powered by AniList's public GraphQL API
// (https://anilist.gitbook.io/anilist-apiv2-docs) — free, no API key, and far
// more reliable than the previous Jikan backend (which was frequently 504-ing).
// Implements Shelf's BookProvider contract (see apps/shelf/server/providers/
// index.js) so the shelf server registers it like any built-in source, mapping
// AniList manga into the common BookResult shape. Contributed by the
// `manga-source` plugin.
const API = 'https://graphql.anilist.co'
const UA = 'Nucleus-Shelf-MangaSource/1.0'

// One request pulls everything we map. SEARCH_MATCH sorts by relevance to the
// query so an exact title (even an obscure one) surfaces first.
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

// AniList descriptions are light HTML/markdown; flatten to plain text.
function stripHtml(s) {
  return String(s || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}

// AniList countryOfOrigin → BCP-47-ish language tag for the Book model.
const LANG_BY_COUNTRY = { JP: 'ja', KR: 'ko', CN: 'zh', TW: 'zh' }

export default class MangaProvider {
  id = 'manga'
  label = 'Manga (AniList)'
  requiresKey = false

  // No API key needed — AniList's GraphQL API is public.
  available() { return true }

  async search(query) {
    const q = String(query || '').trim()
    if (q.length < 2) return []

    // AniList rate-limits (429 with Retry-After). One short retry smooths the
    // common case; anything else just yields no manga (other providers run on).
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

  // Manga aren't indexed by ISBN on AniList, so an ISBN lookup has nothing to
  // resolve. Returning null lets the route fall through to other providers.
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
    // Show the recognisable romaji/native name as a subtitle when it differs.
    const subtitle = [romaji, native].find((t) => t && t !== title) || ''

    // Story/Art staff are the "authors" for a manga; keep unique, in order.
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
