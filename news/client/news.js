// Ported from the iOS plugin's Matching.swift / NewsModel.swift.
const COMMON = new Set(['home', 'love', 'life', 'time', 'news', 'film', 'show', 'away', 'free', 'this', 'that', 'with', 'they', 'them', 'here', 'there', 'what', 'when', 'will', 'nope', 'next', 'more'])

// Names too short or too common to mean the title when they turn up in a sentence.
const matchable = (name) => (name.includes(' ') ? name.length >= 5 : name.length >= 4 && !COMMON.has(name.toLowerCase()))

// Strongest reason first. Single words only count capitalised, so "Dune" matches but "dune buggies" doesn't.
export function interests(movieDNA, library) {
  const terms = []
  const seen = new Set()
  const add = (text, kind) => {
    const name = (text ?? '').trim()
    if (!matchable(name) || seen.has(name.toLowerCase())) return
    seen.add(name.toLowerCase())
    terms.push({ text: name, kind, caseSensitive: !name.includes(' ') })
  }
  for (const p of movieDNA.people) if (p.followed) add(p.name, 'following')
  for (const t of library) if (!t.isCompleted) add(t.title, 'watchlist')
  for (const t of movieDNA.titles) if (t.strength >= 40) add(t.name, 'movieDNA')
  for (const p of movieDNA.people) if (!p.followed && p.strength >= 40) add(p.name, 'person')
  for (const t of library) if (t.isCompleted) add(t.title, 'watchlist')
  return terms
}

const fold = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '')
const isWordChar = (c) => !!c && /[\p{L}\p{N}]/u.test(c)

// A whole-word match, ignoring accents ("Timothée" finds "Timothee").
export function contains(text, name, caseSensitive) {
  const hay = fold(caseSensitive ? text : text.toLowerCase())
  const needle = fold(caseSensitive ? name : name.toLowerCase())
  for (let i = hay.indexOf(needle); i !== -1; i = hay.indexOf(needle, i + 1)) {
    if (!isWordChar(hay[i - 1]) && !isWordChar(hay[i + needle.length])) return true
  }
  return false
}

export const textOf = (a) => `${a.title} ${a.summary}`

export function why(term) {
  const n = term.text
  return {
    following: `Mentions ${n}, whom you follow`,
    person: `Mentions ${n}, from your MovieDNA`,
    watchlist: `About ${n}, on your watchlist`,
    movieDNA: `About ${n}, from your MovieDNA`,
  }[term.kind]
}

export const forYou = (articles, terms) =>
  articles.flatMap((a) => {
    const term = terms.find((t) => contains(textOf(a), t.text, t.caseSensitive))
    return term ? [{ ...a, why: why(term) }] : []
  })

export const mentions = (articles, name) => articles.filter((a) => contains(textOf(a), name, false))

const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
export function ago(iso) {
  if (!iso) return ''
  const s = (new Date(iso) - Date.now()) / 1000
  for (const [unit, secs] of [['day', 86400], ['hour', 3600], ['minute', 60]]) {
    if (Math.abs(s) >= secs) return rtf.format(Math.round(s / secs), unit)
  }
  return 'now'
}
