import { Router } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import MaintenancePreset from './MaintenancePreset.js'
// Core auth-server models/middleware/utils live three levels up — this plugin's
// server dir is mounted at /app/plugins/maintenance/server in the auth-server.
import LocaleConfig from '../../../models/LocaleConfig.js'
import { requireAdmin } from '../../../middleware/auth.js'
import { BASE_LANG } from '../../../utils/locales.js'

const router = Router()

// The static flag file nginx serves at /maintenance.json. Writing it here (while
// the app servers are still up) is what lets the banner persist through a rebuild
// — nginx keeps serving the file after this server goes down. Same file the
// `infra/maintenance` CLI writes; the two are interchangeable.
const STATE_DIR = process.env.STATE_DIR || '/srv/state'
const FLAG = path.join(STATE_DIR, 'maintenance.json')

// Mongoose Map → plain object for JSON responses.
const mapObj = (m) => (m instanceof Map ? Object.fromEntries(m) : (m || {}))

function serializePreset(p) {
  return {
    _id: String(p._id),
    key: p.key,
    builtin: !!p.builtin,
    order: p.order ?? 100,
    level: p.level || 'warning',
    title: mapObj(p.title),
    message: mapObj(p.message),
  }
}

// Turn an ETA argument into human text, mirroring infra/maintenance: a bare
// integer → "~N min"; anything else verbatim; empty → a neutral default.
function formatEta(raw) {
  const s = String(raw ?? '').trim()
  if (!s) return 'a few minutes'
  if (/^[0-9]+$/.test(s)) return `~${s} min`
  return s
}

// Fill {eta} (and the CLI's legacy %ETA%) in a template.
function fillEta(tpl, eta) {
  return String(tpl ?? '').replace(/\{eta\}/g, eta).replace(/%ETA%/g, eta)
}

async function installedLanguages() {
  const cfg = await LocaleConfig.findOne().lean()
  const langs = cfg?.installedLanguages?.length ? cfg.installedLanguages : [BASE_LANG]
  const defaultLang = cfg?.defaultLanguage || BASE_LANG
  return { langs, defaultLang }
}

// Read the flag file if present; null when there's no active maintenance.
function readFlag() {
  try {
    const raw = fs.readFileSync(FLAG, 'utf8')
    const data = JSON.parse(raw)
    return data && data.active ? data : null
  } catch {
    return null
  }
}

// ── Presets (admin) ──────────────────────────────────────────────────────────

router.get('/presets', requireAdmin, async (_req, res) => {
  try {
    const presets = await MaintenancePreset.find().sort({ order: 1, key: 1 }).lean()
    res.json(presets.map(serializePreset))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

const KEY_RE = /^[a-z0-9][a-z0-9-]{0,39}$/

router.post('/presets', requireAdmin, async (req, res) => {
  try {
    const key = String(req.body?.key || '').trim().toLowerCase()
    if (!KEY_RE.test(key)) return res.status(400).json({ error: 'Key must be lowercase letters, digits or dashes (max 40)' })
    if (await MaintenancePreset.findOne({ key })) return res.status(409).json({ error: 'A preset with that key already exists' })
    const title = req.body?.title && typeof req.body.title === 'object' ? req.body.title : {}
    const message = req.body?.message && typeof req.body.message === 'object' ? req.body.message : {}
    if (!String(message[BASE_LANG] || '').trim()) {
      return res.status(400).json({ error: `An English (${BASE_LANG}) message is required` })
    }
    const last = await MaintenancePreset.findOne().sort({ order: -1 }).lean()
    const preset = await MaintenancePreset.create({
      key,
      builtin: false,
      order: (last?.order ?? 100) + 1,
      level: req.body?.level || 'warning',
      title,
      message,
    })
    res.status(201).json(serializePreset(preset))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/presets/:id', requireAdmin, async (req, res) => {
  try {
    const preset = await MaintenancePreset.findById(req.params.id)
    if (!preset) return res.status(404).json({ error: 'Preset not found' })
    // A builtin's key is a stable contract (used by scripts) — don't let it change.
    if (req.body?.key !== undefined && !preset.builtin) {
      const key = String(req.body.key).trim().toLowerCase()
      if (!KEY_RE.test(key)) return res.status(400).json({ error: 'Key must be lowercase letters, digits or dashes (max 40)' })
      const clash = await MaintenancePreset.findOne({ key, _id: { $ne: preset._id } })
      if (clash) return res.status(409).json({ error: 'A preset with that key already exists' })
      preset.key = key
    }
    if (req.body?.level !== undefined) preset.level = req.body.level || 'warning'
    if (req.body?.title && typeof req.body.title === 'object') preset.title = req.body.title
    if (req.body?.message && typeof req.body.message === 'object') {
      if (!String(req.body.message[BASE_LANG] || '').trim()) {
        return res.status(400).json({ error: `An English (${BASE_LANG}) message is required` })
      }
      preset.message = req.body.message
    }
    await preset.save()
    res.json(serializePreset(preset))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/presets/:id', requireAdmin, async (req, res) => {
  try {
    const preset = await MaintenancePreset.findById(req.params.id)
    if (!preset) return res.status(404).json({ error: 'Preset not found' })
    if (preset.builtin) return res.status(400).json({ error: 'Built-in presets can’t be deleted' })
    await preset.deleteOne()
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// ── State (admin) ────────────────────────────────────────────────────────────

// Current banner state + everything the admin page needs to render its controls.
router.get('/status', requireAdmin, async (_req, res) => {
  try {
    const { langs, defaultLang } = await installedLanguages()
    const presets = await MaintenancePreset.find().sort({ order: 1, key: 1 }).lean()
    const flag = readFlag()
    res.json({
      active: !!flag,
      current: flag,
      installedLanguages: langs,
      defaultLanguage: defaultLang,
      presets: presets.map(serializePreset),
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Build the flag payload: title/message rendered for every installed language,
// so the banner can show the viewer's language with no server dependency.
function buildFlag({ langs, defaultLang, preset, eta, custom }) {
  const title = {}
  const message = {}
  const src = custom || { title: mapObj(preset.title), message: mapObj(preset.message) }
  const baseTitle = src.title[defaultLang] || src.title[BASE_LANG] || ''
  const baseMsg = src.message[defaultLang] || src.message[BASE_LANG] || ''
  for (const l of langs) {
    title[l] = fillEta(src.title[l] || baseTitle, eta)
    message[l] = fillEta(src.message[l] || baseMsg, eta)
  }
  return {
    active: true,
    level: (custom ? custom.level : preset.level) || 'warning',
    preset: custom ? 'custom' : preset.key,
    eta,
    defaultLang,
    title,
    message,
    since: new Date().toISOString(),
  }
}

// Raise the banner. Body: { preset: <key>, eta } OR { custom: { title, message, level } }.
router.post('/on', requireAdmin, async (req, res) => {
  try {
    const { langs, defaultLang } = await installedLanguages()
    const eta = formatEta(req.body?.eta)
    let flag

    if (req.body?.custom && typeof req.body.custom === 'object') {
      const c = req.body.custom
      const message = c.message && typeof c.message === 'object' ? c.message : {}
      if (!String(message[defaultLang] || message[BASE_LANG] || '').trim()) {
        return res.status(400).json({ error: 'A message is required' })
      }
      flag = buildFlag({
        langs, defaultLang, eta,
        custom: {
          title: c.title && typeof c.title === 'object' ? c.title : {},
          message,
          level: c.level || 'warning',
        },
      })
    } else {
      const key = String(req.body?.preset || '').trim()
      const preset = await MaintenancePreset.findOne({ key }).lean()
      if (!preset) return res.status(400).json({ error: 'Unknown preset' })
      flag = buildFlag({ langs, defaultLang, eta, preset })
    }

    fs.mkdirSync(STATE_DIR, { recursive: true })
    fs.writeFileSync(FLAG, JSON.stringify(flag, null, 2) + '\n')
    res.json({ active: true, current: flag })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Clear the banner.
router.post('/off', requireAdmin, async (_req, res) => {
  try {
    try { fs.unlinkSync(FLAG) } catch { /* already gone */ }
    res.json({ active: false })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
