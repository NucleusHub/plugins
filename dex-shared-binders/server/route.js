// Shared Binders — server surface.
//
// Mounted by the Dex server at /api/dex/x/dex-shared-binders (see Dex's
// pluginHost.js), which means requireAuth and the app-disabled check have both
// already run: req.profile is populated on every handler here.
//
// This router owns the *management* of sharing — who a binder is shared with,
// and which groups get a group binder. Enforcement lives in binderAccess.js,
// which Dex's own routes consult; the two are deliberately separate so a bug
// here can't hand out access, only mis-record an intent.
//
// Endpoints (all relative to the mount point):
//   GET    /binders/:id/shares          → { shares, role, group, candidates }
//   PUT    /binders/:id/shares          → { shares }         (binder admin)
//   PATCH  /binders/:id/group           → { groupId }        (Nucleus admin)
//   GET    /groups                      → { groups }         (Nucleus admin)
//   POST   /groups/:groupId/binder      → { binder }         (Nucleus admin)
//   POST   /groups/:groupId/teardown    → { ok }             (Nucleus admin)
//
// Paths are relative to /app inside the Dex container: this file is
// /app/plugins/dex-shared-binders/server/route.js, so '../../../models/…'
// reaches Dex's own models. Same convention the in-common plugin uses.
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

// Public-safe profile shape — exactly what AvatarCircle needs, nothing more.
// Read straight off the shared `profiles` collection (all Nucleus services share
// one Mongo database), the same way core/server/appAccess.js reads overrides.
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

// ── Per-binder grants ────────────────────────────────────────────────────────

// GET /binders/:id/shares — who this binder is shared with, plus everyone it
// COULD be shared with, so the share dialog is one request.
router.get('/binders/:id/shares', async (req, res) => {
  try {
    const binder = await Binder.findById(req.params.id).lean().catch(() => null)
    if (!binder) return res.status(404).json({ error: 'Binder not found' })

    const role = await roleFor(binder, req.profile.profileId)
    if (!role) return res.status(404).json({ error: 'Binder not found' })

    const shareIds = (binder.shares ?? []).map((s) => sid(s.profileId))
    const profiles = await loadProfiles([...shareIds, sid(binder.profileId)])

    // Candidates are only listed to someone who could actually act on them.
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

// PUT /binders/:id/shares — replace the grant list wholesale. A whole-list write
// (rather than add/remove verbs) means the dialog's on-screen state IS the
// request, so it can't half-apply.
router.put('/binders/:id/shares', async (req, res) => {
  try {
    const binder = await Binder.findById(req.params.id).lean().catch(() => null)
    if (!binder) return res.status(404).json({ error: 'Binder not found' })

    const role = await roleFor(binder, req.profile.profileId)
    if (!role) return res.status(404).json({ error: 'Binder not found' })
    if (!canManage(role)) return res.status(403).json({ error: 'Not allowed' })

    const incoming = Array.isArray(req.body?.shares) ? req.body.shares : []
    // Dedupe by profile (last wins), drop unknown roles, and never let the owner
    // be given a grant — they already outrank every role and a stale "viewer"
    // row would be a foot-gun waiting for a future refactor.
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

// ── Group binders ────────────────────────────────────────────────────────────
// A group binder is the Dex equivalent of Orbit's shared "Group - {name}"
// directory: the Nucleus admin turns it on for a group, and every member can
// then contribute to one shared binder. Only an admin can bind a binder to a
// group — otherwise any binder admin could quietly publish it to a whole group.

// PATCH /binders/:id/group — attach a binder to a group, or `{ groupId: null }`
// to detach it back to a personal (optionally still individually-shared) binder.
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

// GET /groups — groups with shared binders enabled, and whether each already has
// its binder. Drives the admin-side group binder controls.
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

// POST /groups/:groupId/binder — create the group's shared binder, or return the
// existing one. Idempotent, so the admin panel can call it freely. Mirrors
// Orbit's ensureGroupRoot, including the "Group - {name}" naming.
router.post('/groups/:groupId/binder', requireNucleusAdmin, async (req, res) => {
  try {
    const groupId = oid(req.params.groupId)
    if (!groupId) return res.status(400).json({ error: 'Bad groupId' })

    const group = await mongoose.connection.db.collection('groups').findOne({ _id: groupId })
    if (!group) return res.status(404).json({ error: 'Group not found' })

    const existing = await Binder.findOne({ groupId }).lean()
    if (existing) return res.json({ binder: { id: String(existing._id), name: existing.name }, created: false })

    const binder = await Binder.create({
      // Owned by the admin who created it, so there is always a definite owner —
      // but every member gets `contributor` from the group itself.
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

// POST /groups/:groupId/teardown — called when a group is deleted or has shared
// binders turned off. `{ action: 'transfer', targetProfileId }` keeps the binder
// as that person's personal one; anything else deletes it. Deleting a binder
// never touches anybody's collection — the cards stay where they are.
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
