// Client half of In Common. Every item card mounts its own indicator, but we do
// NOT want one HTTP request per card — so lookups are batched: calls made within
// a short window are coalesced into a single POST per app, and results are
// cached by key for the lifetime of the page (the plugin's data is stable within
// a session). A card just awaits lookup(app, item) and renders whatever profiles
// come back (empty array → no badge).
//
// Batches are bucketed by app AND by scope. Scope matters for Dex: asking "who
// else has this card" is a different question from "is this card already in
// binder X", and the two must not share a cache or a request. Watchlist and
// Shelf pass no scope and get one bucket each, exactly as before.
//
// This file lives in the plugin and is imported by the host apps via their
// `client/plugins` symlink glob, so it ships and versions with the plugin.

const BATCH_MS = 40

// bucket key ("shelf", "dex", "dex|binder:abc123") → per-bucket batch state.
const buckets = new Map()

function bucketFor(key, app, extra) {
  let b = buckets.get(key)
  if (!b) {
    b = { app, extra, cache: new Map(), pending: [], timer: null }
    buckets.set(key, b)
  }
  return b
}

function schedule(b) {
  if (b.timer) return
  b.timer = setTimeout(() => flush(b), BATCH_MS)
}

async function flush(b) {
  b.timer = null
  const batch = b.pending.splice(0)
  if (!batch.length) return

  // Coalesce duplicate keys (the same card can appear on several tiles).
  const resolversByKey = new Map()
  const itemByKey = new Map()
  for (const { item, resolve } of batch) {
    if (!resolversByKey.has(item.key)) resolversByKey.set(item.key, [])
    resolversByKey.get(item.key).push(resolve)
    if (!itemByKey.has(item.key)) itemByKey.set(item.key, item)
  }

  let matches = {}
  try {
    const res = await fetch(`/api/auth/in-common/${b.app}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ items: [...itemByKey.values()], ...(b.extra || {}) }),
    })
    if (res.ok) matches = (await res.json())?.matches ?? {}
  } catch {
    // Plugin server absent / offline → behave as "no overlap", never throw.
  }

  for (const [key, resolvers] of resolversByKey) {
    const profiles = matches[key] ?? []
    b.cache.set(key, profiles)
    resolvers.forEach((r) => r(profiles))
  }
}

/**
 * Resolve the profiles who also have `item` (shape depends on app — see the
 * indicator components). Returns a Promise<profile[]>.
 *
 * @param {string} app    'watchlist' | 'shelf' | 'dex'
 * @param {object} item   must carry a `key`; other fields are the match payload
 * @param {object} [extra] extra request fields that change the QUESTION being
 *                         asked (e.g. `{ binderId }`). Included in the bucket
 *                         key so answers for different scopes never mix.
 */
export function lookup(app, item, extra = null) {
  if (!item || item.key == null) return Promise.resolve([])
  const scope = extra ? JSON.stringify(extra) : ''
  const b = bucketFor(scope ? `${app}|${scope}` : app, app, extra)
  if (b.cache.has(item.key)) return Promise.resolve(b.cache.get(item.key))
  return new Promise((resolve) => {
    b.pending.push({ item, resolve })
    schedule(b)
  })
}

// Drop cached answers for a bucket. Used after a collection change makes a
// previous "nobody else has this" answer stale.
export function invalidate(app, extra = null) {
  const scope = extra ? JSON.stringify(extra) : ''
  buckets.delete(scope ? `${app}|${scope}` : app)
}
