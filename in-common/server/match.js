// Matching helpers shared by the watchlist + shelf lookups. Kept deliberately
// forgiving: the goal is to surface "someone else has this too", not to be a
// strict catalogue join. Both apps source their metadata from the same public
// providers (TMDb / Open Library etc.), so lightly-normalised titles line up
// well in practice.

// Normalise a title/author for fuzzy equality: lowercase, strip accents, drop a
// leading article, and collapse anything non-alphanumeric to single spaces.
export function norm(s) {
  return String(s ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/^(the|a|an)\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

// Normalise an ISBN to its comparable core (digits + trailing X, uppercased).
export function normIsbn(s) {
  const v = String(s ?? '').replace(/[^0-9xX]/g, '').toUpperCase()
  return v.length >= 10 ? v : ''
}

// Candidate keys for a watchlist title. Two items match if they share ANY key:
//   • tmdb:<id>       — exact TMDb match when both sides were added via TMDb
//   • ta:<title>|type — fuzzy fallback that also bridges to older items (and
//                       non-TMDb sources) that have no stored id yet.
// Year is intentionally left out of the fuzzy key — a remake collision is rare
// and far less costly than missing a real overlap.
export function watchlistKeys(item) {
  const keys = []
  const id = item?.tmdbId
  if (id != null && id !== '') keys.push(`tmdb:${id}`)
  const t = norm(item?.title)
  if (t) keys.push(`ta:${t}|${String(item?.type ?? '').toLowerCase()}`)
  return keys
}

// Candidate keys for a Dex card. Unlike watchlist titles and books, there is
// nothing to guess at here: Dex's catalog is a single shared, immutable card
// database, so every user's collection points at the very same cardId. Matching
// is therefore exact, and the "fuzzy join" caveat above doesn't apply.
export function cardKeys(item) {
  const id = item?.cardId ?? item?.key
  return id ? [`card:${String(id)}`] : []
}

// Candidate keys for a book: ISBN, each external identifier, and a
// title+first-author fallback. Two books match if they share ANY key.
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
