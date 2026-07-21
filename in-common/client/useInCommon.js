// Client half of In Common. Every item card mounts its own indicator, but we do
// NOT want one HTTP request per card — so lookups are batched: calls made within
// a short window are coalesced into a single POST per app, and results are
// cached by key for the lifetime of the page (the plugin's data is stable within
// a session). A card just awaits lookup(app, item) and renders whatever profiles
// come back (empty array → no badge).
//
// This file lives in the plugin and is imported by the host apps via their
// `client/plugins` symlink glob, so it ships and versions with the plugin.

const BATCH_MS = 40

const caches = { watchlist: new Map(), shelf: new Map() } // key → profile[]
const pending = { watchlist: [], shelf: [] } // { item, resolve }
const timers = { watchlist: null, shelf: null }

function schedule(app) {
  if (timers[app]) return
  timers[app] = setTimeout(() => flush(app), BATCH_MS)
}

async function flush(app) {
  timers[app] = null
  const batch = pending[app].splice(0)
  if (!batch.length) return

  // Coalesce duplicate keys (the same title can appear on several cards).
  const resolversByKey = new Map()
  const itemByKey = new Map()
  for (const { item, resolve } of batch) {
    if (!resolversByKey.has(item.key)) resolversByKey.set(item.key, [])
    resolversByKey.get(item.key).push(resolve)
    if (!itemByKey.has(item.key)) itemByKey.set(item.key, item)
  }

  let matches = {}
  try {
    const res = await fetch(`/api/auth/in-common/${app}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ items: [...itemByKey.values()] }),
    })
    if (res.ok) matches = (await res.json())?.matches ?? {}
  } catch {
    // Plugin server absent / offline → behave as "no overlap", never throw.
  }

  for (const [key, resolvers] of resolversByKey) {
    const profiles = matches[key] ?? []
    caches[app].set(key, profiles)
    resolvers.forEach((r) => r(profiles))
  }
}

// Resolve the profiles who also have `item` (shape depends on app — see the
// indicator components). Returns a Promise<profile[]>.
export function lookup(app, item) {
  if (!item || item.key == null) return Promise.resolve([])
  const cache = caches[app]
  if (cache.has(item.key)) return Promise.resolve(cache.get(item.key))
  return new Promise((resolve) => {
    pending[app].push({ item, resolve })
    schedule(app)
  })
}
