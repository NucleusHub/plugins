// What the plugin needs from the app it runs in. Inside Nucleus that is the
// home server; the iOS app keeps the watchlist on the device and swaps these
// in through the native bundle's connect().
async function send(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`${method} failed (${res.status})`)
  return res.json()
}

const host = {
  createItem: (body) => send('POST', '/api/watchlist', body),
  updateItem: (id, body) => send('PATCH', `/api/watchlist/${id}`, body),
  tmdbKey: () => import.meta.env.VITE_TMDB_API_KEY || '',
}

export const useHost = () => host

export function connect(overrides = {}) {
  for (const key of Object.keys(host)) {
    if (typeof overrides[key] === 'function') host[key] = overrides[key]
  }
}
