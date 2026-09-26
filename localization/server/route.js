import { Router } from 'express'
import crypto from 'node:crypto'
import LocaleConfig from './LocaleConfig.js'
import LocaleOverride from './LocaleOverride.js'
import { requireAdmin } from '../../../middleware/auth.js'
import {
  BASE_LANG, resolveCatalog, completeness, scopeKeys,
  listScopes, availableLangs, localesSignature,
} from './locales.js'

const router = Router()

async function getConfig() {
  let cfg = await LocaleConfig.findOne()
  if (!cfg) cfg = await LocaleConfig.create({})
  return cfg
}

function enabledObj(cfg) {
  const e = cfg.enabled
  if (!e) return {}
  return e instanceof Map ? Object.fromEntries(e) : e
}

function installableLangs() {
  const set = new Set()
  for (const scope of listScopes()) for (const l of availableLangs(scope)) set.add(l)
  return [...set].sort((a, b) => (a === BASE_LANG ? -1 : b === BASE_LANG ? 1 : a.localeCompare(b)))
}

function catalogVersion(cfg, overrideCount) {
  return crypto.createHash('sha1')
    .update(`${cfg.updatedAt?.getTime() || 0}:${overrideCount}:${localesSignature()}`)
    .digest('hex').slice(0, 12)
}

async function loadOverrides(lang) {
  const rows = await LocaleOverride.find({ lang: { $in: [...new Set([lang, BASE_LANG])] } }).lean()
  const ov = {}
  for (const r of rows) (ov[r.lang] ??= {})[r.key] = r.value
  return ov
}

// Public: the pre-auth login screen needs translations.
router.get('/catalog', async (req, res) => {
  try {
    const cfg = await getConfig()
    const app = (req.query.app || 'core').toString()
    const lang = (req.query.lang || cfg.defaultLanguage || BASE_LANG).toString()
    const ov = await loadOverrides(lang)
    const enabled = enabledObj(cfg)
    const messages = resolveCatalog(app, lang, ov, enabled)
    const appEnabled = (enabled[app] || (app === 'core' ? [BASE_LANG] : [])).includes(lang)
    const overrideCount = await LocaleOverride.estimatedDocumentCount()
    res.json({
      app,
      lang,
      fallbackLang: BASE_LANG,
      availableForApp: lang === BASE_LANG || (app === 'core' || availableLangs(app).includes(lang)) && appEnabled,
      version: catalogVersion(cfg, overrideCount),
      messages,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/config', async (_req, res) => {
  try {
    const cfg = await getConfig()
    res.json({
      installedLanguages: cfg.installedLanguages,
      defaultLanguage: cfg.defaultLanguage,
      enabled: enabledObj(cfg),
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/admin/overview', requireAdmin, async (_req, res) => {
  try {
    const cfg = await getConfig()
    const enabled = enabledObj(cfg)
    const scopes = listScopes().map(scope => ({
      scope,
      availableLangs: availableLangs(scope),
      enabledLangs: enabled[scope] || (scope === 'core' ? [BASE_LANG] : []),
      completeness: Object.fromEntries(
        cfg.installedLanguages.map(lang => [lang, completeness(scope, lang)]),
      ),
    }))
    const enabledLanguages = cfg.installedLanguages.filter(
      l => Object.values(enabled).some(arr => arr.includes(l)),
    )
    res.json({
      installedLanguages: cfg.installedLanguages,
      defaultLanguage: cfg.defaultLanguage,
      installable: installableLangs(),
      enabledLanguages,
      scopes,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/admin/languages', requireAdmin, async (req, res) => {
  try {
    const lang = (req.body?.lang || '').toString()
    if (!lang) return res.status(400).json({ error: 'lang is required' })
    if (!installableLangs().includes(lang)) {
      return res.status(400).json({ error: 'No locale files ship this language' })
    }
    const cfg = await getConfig()
    if (!cfg.installedLanguages.includes(lang)) {
      cfg.installedLanguages.push(lang)
      await cfg.save()
    }
    res.json({ installedLanguages: cfg.installedLanguages })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/admin/languages/:lang', requireAdmin, async (req, res) => {
  try {
    const lang = req.params.lang
    const cfg = await getConfig()
    if (!cfg.installedLanguages.includes(lang)) return res.status(404).json({ error: 'Language is not installed' })
    if (cfg.installedLanguages.length <= 1) return res.status(400).json({ error: 'At least one language must stay installed' })
    cfg.installedLanguages = cfg.installedLanguages.filter(l => l !== lang)
    for (const [scope, langs] of Object.entries(enabledObj(cfg))) {
      cfg.enabled.set(scope, langs.filter(l => l !== lang))
    }
    if (cfg.defaultLanguage === lang) {
      cfg.defaultLanguage = cfg.installedLanguages.includes(BASE_LANG) ? BASE_LANG : cfg.installedLanguages[0]
    }
    await cfg.save()
    res.json({ installedLanguages: cfg.installedLanguages })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/admin/default', requireAdmin, async (req, res) => {
  try {
    const lang = req.body?.lang
    const cfg = await getConfig()
    if (!lang || !cfg.installedLanguages.includes(lang)) {
      return res.status(400).json({ error: 'Language is not installed' })
    }
    cfg.defaultLanguage = lang
    await cfg.save()
    res.json({ defaultLanguage: lang })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/admin/languages/:lang/enabled', requireAdmin, async (req, res) => {
  try {
    const lang = req.params.lang
    const enabled = !!req.body?.enabled
    const cfg = await getConfig()
    if (!cfg.installedLanguages.includes(lang)) return res.status(400).json({ error: 'Language is not installed' })
    const eObj = enabledObj(cfg)
    const enabledAnywhere = l => Object.values(eObj).some(arr => arr.includes(l))

    if (!enabled) {
      const othersEnabled = cfg.installedLanguages.some(l => l !== lang && enabledAnywhere(l))
      if (enabledAnywhere(lang) && !othersEnabled) {
        return res.status(400).json({ error: 'At least one language must stay enabled' })
      }
      for (const [scope, langs] of Object.entries(eObj)) {
        cfg.enabled.set(scope, langs.filter(l => l !== lang))
      }
    } else {
      const core = eObj.core || []
      if (!core.includes(lang)) cfg.enabled.set('core', [...core, lang])
    }
    await cfg.save()
    res.json({ enabled: enabledObj(cfg) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/admin/enabled', requireAdmin, async (req, res) => {
  try {
    const { lang, scope, enabled } = req.body || {}
    if (!lang || !scope) return res.status(400).json({ error: 'lang and scope are required' })
    const cfg = await getConfig()
    if (enabled) {
      if (!cfg.installedLanguages.includes(lang)) return res.status(400).json({ error: 'Language is not installed' })
      if (scope !== 'core' && !availableLangs(scope).includes(lang)) {
        return res.status(400).json({ error: 'This app doesn’t ship that language' })
      }
    }
    const current = cfg.enabled.get(scope) || []
    const next = enabled
      ? [...new Set([...current, lang])]
      : current.filter(l => l !== lang)
    cfg.enabled.set(scope, next)
    await cfg.save()
    res.json({ scope, enabledLangs: next })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/admin/keys', requireAdmin, async (req, res) => {
  try {
    const scope = (req.query.scope || 'core').toString()
    const lang = (req.query.lang || BASE_LANG).toString()
    const overrides = await LocaleOverride.find({ lang }).lean()
    const ovMap = Object.fromEntries(overrides.map(o => [o.key, o.value]))
    const keys = scopeKeys(scope, lang).map(k => ({ ...k, override: ovMap[k.key] ?? null }))
    res.json({ scope, lang, keys })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.put('/admin/overrides', requireAdmin, async (req, res) => {
  try {
    const { lang, key, value } = req.body || {}
    if (!lang || !key || value == null) return res.status(400).json({ error: 'lang, key and value are required' })
    await LocaleOverride.findOneAndUpdate({ lang, key }, { lang, key, value: String(value) }, { upsert: true })
    res.json({ lang, key, value: String(value) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/admin/overrides', requireAdmin, async (req, res) => {
  try {
    const { lang, key } = req.body || {}
    if (!lang || !key) return res.status(400).json({ error: 'lang and key are required' })
    await LocaleOverride.deleteOne({ lang, key })
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
