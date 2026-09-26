import { Router } from 'express'
import mongoose from 'mongoose'
import Profile from '../../../models/Profile.js'
import Group from '../../../models/Group.js'
import { requireAuth, requireAdmin } from '../../../middleware/auth.js'
import InCommonConfig from './InCommonConfig.js'
import { watchlistKeys, bookKeys, cardKeys } from './match.js'

const router = Router()

const MAX_ITEMS = 500

async function currentScope() {
  const cfg = await InCommonConfig.findOne().lean()
  return cfg?.scope === 'group' ? 'group' : 'network'
}

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

function toObjectIds(ids) {
  const out = []
  for (const id of ids) {
    if (mongoose.Types.ObjectId.isValid(id)) out.push(new mongoose.Types.ObjectId(id))
  }
  return out
}

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

router.post('/shelf', requireAuth, async (req, res) => {
  try {
    const items = readItems(req)
    if (!items.length) return res.json({ matches: {} })

    const scope = await currentScope()
    const audience = await audienceIds(req.profile.profileId, scope)
    if (!audience.length) return res.json({ matches: {} })

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

async function binderAudience(binderId, meId) {
  if (!mongoose.Types.ObjectId.isValid(binderId)) return null
  const binder = await mongoose.connection.db
    .collection('dexbinders')
    .findOne(
      { _id: new mongoose.Types.ObjectId(binderId) },
      { projection: { profileId: 1, groupId: 1, shares: 1 } }
    )
  if (!binder) return null

  const ids = new Set([String(binder.profileId)])
  for (const s of binder.shares ?? []) if (s?.profileId) ids.add(String(s.profileId))
  if (binder.groupId) {
    const group = await Group.findById(binder.groupId).select('memberIds').lean()
    for (const m of group?.memberIds ?? []) ids.add(String(m))
  }

  const me = String(meId)
  if (!ids.has(me)) return null
  ids.delete(me)
  return [...ids]
}

router.post('/dex', requireAuth, async (req, res) => {
  try {
    const items = readItems(req)
    if (!items.length) return res.json({ matches: {} })

    const binderId = req.body?.binderId ? String(req.body.binderId) : ''
    let audience
    if (binderId) {
      audience = await binderAudience(binderId, req.profile.profileId)
      // Same answer as an empty scope so binder existence isn't leaked.
      if (!audience) return res.json({ matches: {} })
    } else {
      audience = await audienceIds(req.profile.profileId, await currentScope())
    }
    if (!audience.length) return res.json({ matches: {} })

    const rows = await mongoose.connection.db
      .collection('dexcollectionitems')
      .find(
        { profileId: { $in: toObjectIds(audience) }, cardId: { $in: items.map((it) => String(it.cardId ?? it.key)) } },
        { projection: { profileId: 1, cardId: 1 } },
      )
      .toArray()

    const index = new Map()
    for (const r of rows) {
      for (const k of cardKeys(r)) {
        if (!index.has(k)) index.set(k, new Set())
        index.get(k).add(String(r.profileId))
      }
    }

    const matches = await resolveMatches(items, (it) => cardKeys(it), index)
    res.json({ matches })
  } catch (e) {
    console.error('[in-common] route error:', e)
    res.status(500).json({ error: 'server error' })
  }
})

export default router
