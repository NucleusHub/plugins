const BATCH_MS = 40

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
  }

  for (const [key, resolvers] of resolversByKey) {
    const profiles = matches[key] ?? []
    b.cache.set(key, profiles)
    resolvers.forEach((r) => r(profiles))
  }
}

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

export function invalidate(app, extra = null) {
  const scope = extra ? JSON.stringify(extra) : ''
  buckets.delete(scope ? `${app}|${scope}` : app)
}
