// A person's work as their page shows it; port of native/Sources/Filmography.swift.
export const APPEARANCES = 'Appearances'

const year = (date) => (date && date.length >= 4 ? date.slice(0, 4) : null)

// One entry per title, newest first; titles without a date (announced) on top.
function merge(credits) {
  const merged = new Map()
  for (const c of credits) {
    const key = `${c.kind}-${c.titleID}`
    const prev = merged.get(key)
    if (prev) {
      if (c.role && !prev.roles.includes(c.role)) prev.roles.push(c.role)
      prev.date ||= c.date
      prev.posterURL ||= c.posterURL
      prev.voteCount = Math.max(prev.voteCount, c.voteCount)
    } else {
      merged.set(key, { key, titleID: c.titleID, kind: c.kind, title: c.title, date: c.date, posterURL: c.posterURL, roles: c.role ? [c.role] : [], voteCount: c.voteCount })
    }
  }
  return [...merged.values()].sort((a, b) => (b.date || '9999').localeCompare(a.date || '9999')).map((e) => ({ ...e, year: year(e.date) }))
}

function occupation(department, job) {
  switch (department) {
    case 'Acting': return 'Actor'
    case 'Directing': return !job || job === 'Director' ? 'Director' : null
    case 'Writing': return job === 'Creator' ? 'Creator' : 'Writer'
    case 'Production': return job.includes('Casting') ? null : 'Producer'
    case 'Sound': return job.includes('Composer') || job === 'Music' || !job ? 'Composer' : null
    case 'Camera': return job === 'Director of Photography' || !job ? 'Cinematographer' : null
    case 'Editing': return job === 'Editor' || !job ? 'Editor' : null
    case 'Creator': return 'Creator'
    default: return null
  }
}

// What they are, most defining first: "Actor", "Director", "Producer"...
function occupations(person, credits) {
  const counts = new Map()
  for (const c of credits) {
    if (c.isSelf) continue
    const name = occupation(c.department, c.role)
    if (name) counts.set(name, (counts.get(name) || 0) + 1)
  }
  const main = person.knownFor ? occupation(person.knownFor, '') : null
  const ranked = [...counts.keys()].sort((a, b) =>
    (a === main) !== (b === main) ? (a === main ? -1 : 1) : counts.get(b) - counts.get(a) || a.localeCompare(b))
  // A one-off job isn't an occupation, unless it's all they did.
  const solid = ranked.filter((o) => o === main || counts.get(o) >= 2)
  return (solid.length ? solid : ranked).slice(0, 4)
}

export function filmography(person) {
  const credits = person.credits.filter((c) => c.title)
  const byGroup = new Map()
  for (const c of credits) {
    const group = c.isSelf ? APPEARANCES : c.department
    byGroup.set(group, [...(byGroup.get(group) ?? []), c])
  }
  // Their main department first, then by how much they did; appearances always last.
  const order = [...byGroup.keys()].sort((a, b) => {
    if ((a === APPEARANCES) !== (b === APPEARANCES)) return a === APPEARANCES ? 1 : -1
    if ((a === person.knownFor) !== (b === person.knownFor)) return a === person.knownFor ? -1 : 1
    const ca = byGroup.get(a).length
    const cb = byGroup.get(b).length
    return ca !== cb ? cb - ca : a.localeCompare(b)
  })
  // Well-known titles from what they're known for, not talk-show visits.
  const main = credits.filter((c) => c.department === (person.knownFor ?? c.department) && !c.isSelf)
  return {
    occupations: occupations(person, credits),
    knownFor: merge(main.length ? main : credits).sort((a, b) => b.voteCount - a.voteCount).slice(0, 10),
    groups: order.map((id) => ({ id, entries: merge(byGroup.get(id)) })),
  }
}
