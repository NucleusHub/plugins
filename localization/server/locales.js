import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

export const BASE_LANG = 'en-US'

const CORE_DIR = process.env.CORE_LOCALES_DIR || '/core-locales'
const APPS_DIR = process.env.APPS_DIR || '/apps'
const HUB_DIR = process.env.HUB_LOCALES_DIR || '/hub-locales'

let cache = null

function safeReaddir(dir, opts) {
  try { return fs.readdirSync(dir, opts) } catch { return [] }
}

function listLocaleFiles() {
  const out = []
  for (const f of safeReaddir(CORE_DIR)) {
    if (f.endsWith('.json')) out.push({ scope: 'core', lang: f.slice(0, -5), file: path.join(CORE_DIR, f) })
  }
  for (const f of safeReaddir(HUB_DIR)) {
    if (f.endsWith('.json')) out.push({ scope: 'hub', lang: f.slice(0, -5), file: path.join(HUB_DIR, f) })
  }
  for (const entry of safeReaddir(APPS_DIR, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue
    const dir = path.join(APPS_DIR, entry.name, 'locales')
    for (const f of safeReaddir(dir)) {
      if (f.endsWith('.json')) out.push({ scope: entry.name, lang: f.slice(0, -5), file: path.join(dir, f) })
    }
  }
  return out
}

function signature(files) {
  return files
    .map(f => { try { return `${f.file}:${fs.statSync(f.file).mtimeMs}` } catch { return `${f.file}:0` } })
    .sort()
    .join('|')
}

function build() {
  const files = listLocaleFiles()
  const sig = signature(files)
  if (cache && cache.sig === sig) return cache

  const index = {}
  const availableLangs = {}
  for (const { scope, lang, file } of files) {
    let json
    try { json = JSON.parse(fs.readFileSync(file, 'utf8')) } catch { continue }
    if (!json || typeof json !== 'object' || Array.isArray(json)) continue
    ;(index[scope] ??= {})[lang] = json
    ;(availableLangs[scope] ??= new Set()).add(lang)
  }
  cache = { index, availableLangs, sig }
  return cache
}

export function localesSignature() {
  return crypto.createHash('sha1').update(build().sig).digest('hex').slice(0, 12)
}

export function listScopes() {
  const { index } = build()
  const scopes = Object.keys(index).filter(s => s !== 'core').sort()
  return ['core', ...scopes]
}

export function availableLangs(scope) {
  const set = build().availableLangs[scope]
  if (!set) return []
  return [...set].sort((a, b) => (a === BASE_LANG ? -1 : b === BASE_LANG ? 1 : a.localeCompare(b)))
}

function effectiveLang(scope, lang, enabledByScope) {
  if (lang === BASE_LANG || !enabledByScope) return lang
  const enabled = enabledByScope[scope] || []
  return enabled.includes(lang) ? lang : BASE_LANG
}

export function resolveCatalog(app, lang, ov = {}, enabledByScope = null) {
  const { index } = build()
  const scopes = ['core']
  if (app && app !== 'core') scopes.push(app)
  const messages = {}

  for (const scope of scopes) {
    const eff = effectiveLang(scope, lang, enabledByScope)
    const byLang = index[scope] || {}
    const base = byLang[BASE_LANG] || {}
    const loc = byLang[eff] || {}
    for (const key of new Set([...Object.keys(base), ...Object.keys(loc)])) {
      messages[key] = ov[eff]?.[key] ?? loc[key] ?? ov[BASE_LANG]?.[key] ?? base[key] ?? key
    }

    for (const oLang of new Set([eff, BASE_LANG])) {
      for (const key of Object.keys(ov[oLang] || {})) {
        if ((key === scope || key.startsWith(`${scope}.`)) && !(key in messages)) {
          messages[key] = ov[eff]?.[key] ?? ov[BASE_LANG]?.[key]
        }
      }
    }
  }
  return messages
}

export function completeness(scope, lang) {
  const byLang = build().index[scope] || {}
  const base = byLang[BASE_LANG] || {}
  const loc = byLang[lang] || {}
  const baseKeys = Object.keys(base)
  const missingKeys = baseKeys.filter(k => !(k in loc))
  return { total: baseKeys.length, missing: missingKeys.length, missingKeys }
}

export function scopeKeys(scope, lang) {
  const byLang = build().index[scope] || {}
  const base = byLang[BASE_LANG] || {}
  const loc = byLang[lang] || {}
  return Object.keys(base).sort().map(key => ({ key, base: base[key], value: loc[key] ?? null }))
}
