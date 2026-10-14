// Finds a person's Wikipedia article through the Wikidata id TMDb gives, in the browser's language when there is one.
const cache = new Map()

export async function wikipediaArticle(wikidataID) {
  const id = String(wikidataID).replace(/[^A-Za-z0-9]/g, '')
  if (!id) return null
  if (!cache.has(id)) {
    const url = `https://www.wikidata.org/w/api.php?action=wbgetentities&ids=${id}&props=sitelinks/urls&format=json&origin=*`
    cache.set(id, fetch(url).then((r) => (r.ok ? r.json() : null)).then((data) => {
      const links = data?.entities?.[id]?.sitelinks ?? {}
      const languages = [...new Set([...navigator.languages.map((l) => l.split('-')[0]), 'en'])]
      return languages.map((l) => links[`${l}wiki`]?.url).find(Boolean) ?? null
    }).catch(() => null))
  }
  return cache.get(id)
}
