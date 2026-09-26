import { Router } from 'express'
import mongoose from 'mongoose'
import WhatsNewAnnouncement from './WhatsNewAnnouncement.js'
import Profile from '../../../models/Profile.js'
import { requireAuth, requireAdmin } from '../../../middleware/auth.js'

// Inlined so What's New works without the localization plugin.
const BASE_LANG = 'en-US'

const router = Router()

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
  const LocaleConfig = mongoose.models.LocaleConfig
  const cfg = LocaleConfig ? await LocaleConfig.findOne().lean() : null
  const langs = cfg?.installedLanguages?.length ? cfg.installedLanguages : [BASE_LANG]
  const defaultLang = cfg?.defaultLanguage || BASE_LANG
  return { langs, defaultLang }
}

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

router.post('/announcements/:id/publish', requireAdmin, async (req, res) => {
  try {
    const a = await WhatsNewAnnouncement.findById(req.params.id)
    if (!a) return res.status(404).json({ error: 'Announcement not found' })
    a.published = true
    // Stamp only once so re-publishing doesn't re-open the modal for everyone.
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
