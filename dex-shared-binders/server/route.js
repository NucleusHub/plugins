import { Router } from 'express'
import mongoose from 'mongoose'
import Binder from '../../../models/Binder.js'
import { roleFor, canManage } from '../../../utils/binderAccess.js'

const router = Router()

const VALID_ROLES = ['viewer', 'contributor', 'admin']
const sid = (v) => (v == null ? '' : String(v))

const isAdmin = (req) => req.profile?.role === 'admin'
function requireNucleusAdmin(req, res, next) {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin required' })
  next()
}

const oid = (v) => (mongoose.Types.ObjectId.isValid(v) ? new mongoose.Types.ObjectId(v) : null)

async function loadProfiles(ids) {
  const objectIds = ids.map(oid).filter(Boolean)
  if (!objectIds.length) return new Map()
  const docs = await mongoose.connection.db
    .collection('profiles')
    .find({ _id: { $in: objectIds } }, { projection: { name: 1, emoji: 1, color: 1, image: 1, imageUpdatedAt: 1, role: 1 } })
    .toArray()
  return new Map(
    docs.map((p) => [
      String(p._id),
      {
        profileId: String(p._id),
        name: p.name,
        emoji: p.emoji ?? null,
        color: p.color,
        role: p.role,
        hasImage: !!p.image,
        imageUpdatedAt: p.imageUpdatedAt ?? null,
      },
    ])
  )
}

router.get('/binders/:id/shares', async (req, res) => {
  try {
    const binder = await Binder.findById(req.params.id).lean().catch(() => null)
    if (!binder) return res.status(404).json({ error: 'Binder not found' })

    const role = await roleFor(binder, req.profile.profileId)
    if (!role) return res.status(404).json({ error: 'Binder not found' })

    const shareIds = (binder.shares ?? []).map((s) => sid(s.profileId))
    const profiles = await loadProfiles([...shareIds, sid(binder.profileId)])

    let candidates = []
    if (canManage(role)) {
      const exclude = new Set([...shareIds, sid(binder.profileId)])
      const all = await mongoose.connection.db
        .collection('profiles')
        .find({ isGuest: { $ne: true } }, { projection: { name: 1, emoji: 1, color: 1, image: 1, imageUpdatedAt: 1, role: 1 } })
        .toArray()
      candidates = all
        .filter((p) => !exclude.has(String(p._id)))
        .map((p) => ({
          profileId: String(p._id),
          name: p.name,
          emoji: p.emoji ?? null,
          color: p.color,
          role: p.role,
          hasImage: !!p.image,
          imageUpdatedAt: p.imageUpdatedAt ?? null,
        }))
        .sort((a, b) => a.name.localeCompare(b.name))
    }

    let group = null
    if (binder.groupId) {
      const g = await mongoose.connection.db
        .collection('groups')
        .findOne({ _id: binder.groupId }, { projection: { name: 1, memberIds: 1 } })
      if (g) group = { groupId: String(g._id), name: g.name, memberCount: (g.memberIds ?? []).length }
    }

    res.json({
      role,
      canManage: canManage(role),
      owner: profiles.get(sid(binder.profileId)) ?? null,
      shares: (binder.shares ?? [])
        .map((s) => ({ ...(profiles.get(sid(s.profileId)) ?? { profileId: sid(s.profileId), name: '—' }), grant: s.role }))
        .sort((a, b) => a.name.localeCompare(b.name)),
      group,
      candidates,
    })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(500).json({ error: 'server error' })
  }
})

router.put('/binders/:id/shares', async (req, res) => {
  try {
    const binder = await Binder.findById(req.params.id).lean().catch(() => null)
    if (!binder) return res.status(404).json({ error: 'Binder not found' })

    const role = await roleFor(binder, req.profile.profileId)
    if (!role) return res.status(404).json({ error: 'Binder not found' })
    if (!canManage(role)) return res.status(403).json({ error: 'Not allowed' })

    const incoming = Array.isArray(req.body?.shares) ? req.body.shares : []
    const byProfile = new Map()
    for (const s of incoming) {
      const pid = oid(s?.profileId)
      if (!pid) continue
      if (sid(pid) === sid(binder.profileId)) continue
      const grant = VALID_ROLES.includes(s?.role) ? s.role : 'viewer'
      byProfile.set(sid(pid), { profileId: pid, role: grant })
    }

    const updated = await Binder.findByIdAndUpdate(
      req.params.id,
      { $set: { shares: [...byProfile.values()] } },
      { new: true }
    ).lean()

    res.json({ shares: (updated.shares ?? []).map((s) => ({ profileId: sid(s.profileId), role: s.role })) })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(400).json({ error: err.message })
  }
})

router.patch('/binders/:id/group', requireNucleusAdmin, async (req, res) => {
  try {
    const raw = req.body?.groupId
    const groupId = raw == null || raw === '' ? null : oid(raw)
    if (raw && !groupId) return res.status(400).json({ error: 'Bad groupId' })

    if (groupId) {
      const group = await mongoose.connection.db.collection('groups').findOne({ _id: groupId })
      if (!group) return res.status(404).json({ error: 'Group not found' })
      if (!group.sharedDex) {
        return res.status(400).json({ error: 'That group does not have shared binders enabled' })
      }
    }

    const binder = await Binder.findByIdAndUpdate(req.params.id, { $set: { groupId } }, { new: true }).lean()
    if (!binder) return res.status(404).json({ error: 'Binder not found' })
    res.json({ groupId: binder.groupId ? String(binder.groupId) : null })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(400).json({ error: err.message })
  }
})

router.get('/groups', requireNucleusAdmin, async (_req, res) => {
  try {
    const groups = await mongoose.connection.db
      .collection('groups')
      .find({ sharedDex: true }, { projection: { name: 1, memberIds: 1 } })
      .toArray()
    const binders = await Binder.find({ groupId: { $in: groups.map((g) => g._id) } })
      .select('groupId name')
      .lean()
    const byGroup = new Map(binders.map((b) => [sid(b.groupId), { id: String(b._id), name: b.name }]))
    res.json({
      groups: groups.map((g) => ({
        groupId: String(g._id),
        name: g.name,
        memberCount: (g.memberIds ?? []).length,
        binder: byGroup.get(String(g._id)) ?? null,
      })),
    })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(500).json({ error: 'server error' })
  }
})

router.post('/groups/:groupId/binder', requireNucleusAdmin, async (req, res) => {
  try {
    const groupId = oid(req.params.groupId)
    if (!groupId) return res.status(400).json({ error: 'Bad groupId' })

    const group = await mongoose.connection.db.collection('groups').findOne({ _id: groupId })
    if (!group) return res.status(404).json({ error: 'Group not found' })

    const existing = await Binder.findOne({ groupId }).lean()
    if (existing) return res.json({ binder: { id: String(existing._id), name: existing.name }, created: false })

    const binder = await Binder.create({
      profileId: req.profile.profileId,
      groupId,
      name: `Group - ${group.name}`,
      layout: req.body?.layout === '2x2' ? '2x2' : '3x3',
      pageCount: 1,
    })
    res.status(201).json({ binder: { id: String(binder._id), name: binder.name }, created: true })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(400).json({ error: err.message })
  }
})

router.post('/groups/:groupId/teardown', requireNucleusAdmin, async (req, res) => {
  try {
    const groupId = oid(req.params.groupId)
    if (!groupId) return res.status(400).json({ error: 'Bad groupId' })

    const binders = await Binder.find({ groupId }).select('_id').lean()
    if (!binders.length) return res.json({ ok: true, empty: true })

    if (req.body?.action === 'transfer') {
      const target = oid(req.body?.targetProfileId)
      if (!target) return res.status(400).json({ error: 'targetProfileId required' })
      await Binder.updateMany({ groupId }, { $set: { profileId: target, groupId: null, shares: [] } })
      return res.json({ ok: true, transferred: binders.length })
    }

    await Binder.deleteMany({ groupId })
    res.json({ ok: true, deleted: binders.length })
  } catch (err) {
    console.error('[dex-shared-binders] route error:', err)
    res.status(400).json({ error: err.message })
  }
})

export default router
