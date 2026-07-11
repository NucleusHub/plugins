import { Router } from 'express'
import WhatsNewAnnouncement from './WhatsNewAnnouncement.js'
// Core auth-server models/middleware/utils live three levels up — this plugin's
// server dir is mounted at /app/plugins/whats-new/server in the auth-server.
import Profile from '../../../models/Profile.js'
import LocaleConfig from '../../../models/LocaleConfig.js'
import { requireAuth, requireAdmin } from '../../../middleware/auth.js'
import { BASE_LANG } from '../../../utils/locales.js'

const router = Router()

// Mongoose Map (or lean plain object) → plain object for JSON responses.
const mapObj = (m) => (m instanceof Map ? Object.fromEntries(m) : (m || {}))

function serializeAnnouncement(a) {
  return {
    _id: String(a._id),
    version: a.version,
    published: !!a.published,
    publishedAt: a.publishedAt || null,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
    entries: (a.entries || []).map(e => ({
      app: e.app,
      version: e.version || '',
      features: (e.features || []).map(f => ({
        title: mapObj(f.title),
        body: mapObj(f.body),
        icon: f.icon || null,
      })),
    })),
  }
}

async function installedLanguages() {
  const cfg = await LocaleConfig.findOne().lean()
  const langs = cfg?.installedLanguages?.length ? cfg.installedLanguages : [BASE_LANG]
  const defaultLang = cfg?.defaultLanguage || BASE_LANG
  return { langs, defaultLang }
}

// Coerce a client-supplied entries array into the stored shape, dropping junk.
function sanitizeEntries(raw) {
  if (!Array.isArray(raw)) return []
  return raw
    .filter(e => e && typeof e.app === 'string' && e.app.trim())
    .map(e => ({
      app: e.app.trim().slice(0, 40),
      version: String(e.version || '').slice(0, 40),
      features: Array.isArray(e.features)
        ? e.features.map(f => ({
            title: f?.title && typeof f.title === 'object' ? f.title : {},
            body: f?.body && typeof f.body === 'object' ? f.body : {},
            icon: f?.icon ? String(f.icon).slice(0, 64) : null,
          }))
        : [],
    }))
}

// ── User-facing feed ──────────────────────────────────────────────────────────

// The cumulative changelog: every published announcement, newest first. The
// client compares the latest publishedAt against the viewer's
// profile.whatsNew.lastSeenAt to decide whether to auto-open.
router.get('/feed', requireAuth, async (_req, res) => {
  try {
    const { langs, defaultLang } = await installedLanguages()
    const announcements = await WhatsNewAnnouncement.find({ published: true })
      .sort({ publishedAt: -1 })
      .lean()
    res.json({
      announcements: announcements.map(serializeAnnouncement),
      installedLanguages: langs,
      defaultLanguage: defaultLang,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Mark the changelog as seen up to now — stops it auto-opening until the next
// announcement is published.
router.post('/seen', requireAuth, async (req, res) => {
  try {
    await Profile.updateOne(
      { _id: req.profile.profileId },
      { $set: { 'whatsNew.lastSeenAt': new Date() } },
    )
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Permanent opt-out (or re-enable) of the What's New modal.
router.post('/opt-out', requireAuth, async (req, res) => {
  try {
    const optOut = !!req.body?.optOut
    await Profile.updateOne(
      { _id: req.profile.profileId },
      { $set: { 'whatsNew.optOut': optOut } },
    )
    res.json({ ok: true, optOut })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// ── Announcements (admin) ──────────────────────────────────────────────────────

router.get('/announcements', requireAdmin, async (_req, res) => {
  try {
    const { langs, defaultLang } = await installedLanguages()
    const list = await WhatsNewAnnouncement.find().sort({ createdAt: -1 }).lean()
    res.json({
      announcements: list.map(serializeAnnouncement),
      installedLanguages: langs,
      defaultLanguage: defaultLang,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/announcements', requireAdmin, async (req, res) => {
  try {
    const version = String(req.body?.version || '').trim().slice(0, 40)
    if (!version) return res.status(400).json({ error: 'A version label is required' })
    const a = await WhatsNewAnnouncement.create({
      version,
      published: false,
      entries: sanitizeEntries(req.body?.entries),
    })
    res.status(201).json(serializeAnnouncement(a))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/announcements/:id', requireAdmin, async (req, res) => {
  try {
    const a = await WhatsNewAnnouncement.findById(req.params.id)
    if (!a) return res.status(404).json({ error: 'Announcement not found' })
    if (req.body?.version !== undefined) {
      const version = String(req.body.version).trim().slice(0, 40)
      if (!version) return res.status(400).json({ error: 'A version label is required' })
      a.version = version
    }
    if (req.body?.entries !== undefined) a.entries = sanitizeEntries(req.body.entries)
    await a.save()
    res.json(serializeAnnouncement(a))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/announcements/:id', requireAdmin, async (req, res) => {
  try {
    const a = await WhatsNewAnnouncement.findById(req.params.id)
    if (!a) return res.status(404).json({ error: 'Announcement not found' })
    await a.deleteOne()
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Publish: stamp publishedAt only on first publish, so editing/re-publishing an
// existing note never re-pops the modal for users who already saw it.
router.post('/announcements/:id/publish', requireAdmin, async (req, res) => {
  try {
    const a = await WhatsNewAnnouncement.findById(req.params.id)
    if (!a) return res.status(404).json({ error: 'Announcement not found' })
    a.published = true
    if (!a.publishedAt) a.publishedAt = new Date()
    await a.save()
    res.json(serializeAnnouncement(a))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/announcements/:id/unpublish', requireAdmin, async (req, res) => {
  try {
    const a = await WhatsNewAnnouncement.findById(req.params.id)
    if (!a) return res.status(404).json({ error: 'Announcement not found' })
    a.published = false
    await a.save()
    res.json(serializeAnnouncement(a))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
