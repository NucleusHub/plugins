// In Common — server surface. Mounted by the auth-server at /api/auth/in-common
// (see core/auth-server/routes/index.js), the same way the maintenance and
// what's-new core plugins are. It lives here rather than in the watchlist/shelf
// app servers because the "who else has this" question spans identities, groups
// AND both apps' item collections — and every service shares the one `nucleus`
// Mongo database, so this router can read all of them off its own connection.
//
// Endpoints:
//   GET   /config              → { scope }                       (any signed-in user)
//   PATCH /config   { scope }  → { scope }                       (admin only)
//   POST  /watchlist { items } → { matches: { key: profile[] } } (any signed-in user)
//   POST  /shelf     { items } → { matches: { key: profile[] } } (any signed-in user)
//
// The lookups only ever return OTHER people (never the caller) and only within
// the configured scope, so nobody learns about libraries they're not already
// grouped with (or, in network mode, that the install is deliberately open).
import { Router } from 'express'
import mongoose from 'mongoose'
import Profile from '../../../models/Profile.js'
import Group from '../../../models/Group.js'
import { requireAuth, requireAdmin } from '../../../middleware/auth.js'
import InCommonConfig from './InCommonConfig.js'
import { watchlistKeys, bookKeys } from './match.js'

const router = Router()

// Guard against a client flooding a single request. A personal library is far
// smaller than this; the cap just bounds worst-case work.
const MAX_ITEMS = 500

// Resolve the active scope, defaulting to 'network' when unset (see the model).
async function currentScope() {
  const cfg = await InCommonConfig.findOne().lean()
  return cfg?.scope === 'group' ? 'group' : 'network'
}

// The set of OTHER profile ids the viewer is allowed to see overlaps with.
//   group   → union of every group the viewer is a member of, minus the viewer
//   network → every non-guest profile, minus the viewer
async function audienceIds(meId, scope) {
  const me = String(meId)
  if (scope === 'group') {
    const groups = await Group.find({ memberIds: me }).select('memberIds').lean()
    const ids = new Set()
    for (const g of groups) for (const m of g.memberIds) if (String(m) !== me) ids.add(String(m))
    return [...ids]
  }
  const all = await Profile.find({ isGuest: { $ne: true } }).select('_id').lean()
  return all.map((p) => String(p._id)).filter((id) => id !== me)
}

// Turn profile-id strings into ObjectIds for a query, skipping any malformed id.
function toObjectIds(ids) {
  const out = []
  for (const id of ids) {
    if (mongoose.Types.ObjectId.isValid(id)) out.push(new mongoose.Types.ObjectId(id))
  }
  return out
}

// Public-safe profile shape the client badge/popover renders (AvatarCircle +
// avatarUrl consume exactly these fields). Never leaks PINs, emails, etc.
async function loadProfiles(ids) {
  if (!ids.length) return {}
  const docs = await Profile.find({ _id: { $in: toObjectIds(ids) } })
    .select('name emoji color image imageUpdatedAt role')
    .lean()
  const map = {}
  for (const p of docs) {
    map[String(p._id)] = {
      profileId: String(p._id),
      name: p.name,
      emoji: p.emoji ?? null,
      color: p.color,
      role: p.role,
      hasImage: !!p.image,
      imageUpdatedAt: p.imageUpdatedAt ?? null,
    }
  }
  return map
}

function readItems(req) {
  const items = Array.isArray(req.body?.items) ? req.body.items : []
  return items.slice(0, MAX_ITEMS).filter((it) => it && it.key != null)
}

// Given an index (sig/key → Set(profileId)) and the requested items, resolve
// each item's owners to full profile objects in a single profile lookup.
async function resolveMatches(items, keysFor, index) {
  const perKey = {}
  const union = new Set()
  for (const it of items) {
    const owners = new Set()
    for (const k of keysFor(it)) {
      const set = index.get(k)
      if (set) for (const pid of set) owners.add(pid)
    }
    if (owners.size) {
      perKey[it.key] = [...owners]
      owners.forEach((o) => union.add(o))
    }
  }
  const profiles = await loadProfiles([...union])
  const matches = {}
  for (const [key, ids] of Object.entries(perKey)) {
    const list = ids.map((id) => profiles[id]).filter(Boolean)
    if (list.length) matches[key] = list
  }
  return matches
}

// ── Admin-controlled scope setting ───────────────────────────────────────────

router.get('/config', requireAuth, async (_req, res) => {
  try {
    res.json({ scope: await currentScope() })
  } catch (e) {
    console.error('[in-common] route error:', e)
    res.status(500).json({ error: 'server error' })
  }
})

router.patch('/config', requireAdmin, async (req, res) => {
  try {
    const scope = req.body?.scope === 'group' ? 'group' : 'network'
    await InCommonConfig.findOneAndUpdate({}, { scope }, { upsert: true, new: true })
    res.json({ scope })
  } catch (e) {
    console.error('[in-common] route error:', e)
    res.status(500).json({ error: 'server error' })
  }
})

// ── Watchlist overlap ────────────────────────────────────────────────────────

router.post('/watchlist', requireAuth, async (req, res) => {
  try {
    const items = readItems(req)
    if (!items.length) return res.json({ matches: {} })

    const scope = await currentScope()
    const audience = await audienceIds(req.profile.profileId, scope)
    if (!audience.length) return res.json({ matches: {} })

    const rows = await mongoose.connection.db
      .collection('watchlistitems')
      .find(
        { profileId: { $in: toObjectIds(audience) } },
        { projection: { profileId: 1, title: 1, type: 1, tmdbId: 1 } },
      )
      .toArray()

    const index = new Map()
    for (const r of rows) {
      const pid = String(r.profileId)
      for (const k of watchlistKeys(r)) {
        if (!index.has(k)) index.set(k, new Set())
        index.get(k).add(pid)
      }
    }

    const matches = await resolveMatches(items, (it) => watchlistKeys(it), index)
    res.json({ matches })
  } catch (e) {
    console.error('[in-common] route error:', e)
    res.status(500).json({ error: 'server error' })
  }
})

// ── Shelf overlap ────────────────────────────────────────────────────────────

router.post('/shelf', requireAuth, async (req, res) => {
  try {
    const items = readItems(req)
    if (!items.length) return res.json({ matches: {} })

    const scope = await currentScope()
    const audience = await audienceIds(req.profile.profileId, scope)
    if (!audience.length) return res.json({ matches: {} })

    // Each user has their OWN Book document (Shelf stores one Book per work per
    // profile), so overlap is matched on ISBN / identifiers / title+author —
    // never on a shared Book _id.
    const rows = await mongoose.connection.db
      .collection('shelfbooks')
      .find(
        { profileId: { $in: toObjectIds(audience) } },
        { projection: { profileId: 1, isbn: 1, identifiers: 1, title: 1, authors: 1 } },
      )
      .toArray()

    const index = new Map()
    for (const r of rows) {
      const pid = String(r.profileId)
      for (const k of bookKeys(r)) {
        if (!index.has(k)) index.set(k, new Set())
        index.get(k).add(pid)
      }
    }

    const matches = await resolveMatches(items, (it) => bookKeys(it), index)
    res.json({ matches })
  } catch (e) {
    console.error('[in-common] route error:', e)
    res.status(500).json({ error: 'server error' })
  }
})

export default router
