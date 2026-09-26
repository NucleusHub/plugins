export function norm(s) {
  return String(s ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/^(the|a|an)\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

export function normIsbn(s) {
  const v = String(s ?? '').replace(/[^0-9xX]/g, '').toUpperCase()
  return v.length >= 10 ? v : ''
}

export function watchlistKeys(item) {
  const keys = []
  const id = item?.tmdbId
  if (id != null && id !== '') keys.push(`tmdb:${id}`)
  const t = norm(item?.title)
  if (t) keys.push(`ta:${t}|${String(item?.type ?? '').toLowerCase()}`)
  return keys
}

export function cardKeys(item) {
  const id = item?.cardId ?? item?.key
  return id ? [`card:${String(id)}`] : []
}

export function bookKeys(book) {
  const keys = []
  const isbn = normIsbn(book?.isbn)
  if (isbn) keys.push(`isbn:${isbn}`)
  const ident = book?.identifiers
  if (ident && typeof ident === 'object') {
    for (const [k, v] of Object.entries(ident)) {
      if (v == null) continue
      const val = String(v).trim().toLowerCase()
      if (val) keys.push(`id:${k}:${val}`)
    }
  }
  const title = norm(book?.title)
  const firstAuthor = norm(Array.isArray(book?.authors) ? book.authors[0] : book?.authors)
  if (title) keys.push(`ta:${title}|${firstAuthor}`)
  return keys
}
