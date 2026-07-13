import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'

// Base/fallback language. Its keys define the "complete" set every other
// language is measured against.
export const BASE_LANG = 'en-US'

// Shipped locale files are read from disk (mounted read-only into the
// auth-server container — see infra/docker-compose.yml). Core strings live in
// CORE_LOCALES_DIR under the 'core' scope; each app ships APPS_DIR/<app>/locales.
const CORE_DIR = process.env.CORE_LOCALES_DIR || '/core-locales'
const APPS_DIR = process.env.APPS_DIR || '/apps'
// Hub is the top-level shell (not under apps/), so its locales are mounted
// separately and scanned under the 'hub' scope.
const HUB_DIR = process.env.HUB_LOCALES_DIR || '/hub-locales'

let cache = null // { index, availableLangs, sig }

function safeReaddir(dir, opts) {
  try { return fs.readdirSync(dir, opts) } catch { return [] }
}

// Enumerate every locale file as { scope, lang, file }. Scope is 'core' for the
// core dir, else the app directory name.
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

// A signature over the set of files and their mtimes; changes whenever a locale
// file is added, removed, or edited, so the cache refreshes without a restart.
function signature(files) {
  return files
    .map(f => { try { return `${f.file}:${fs.statSync(f.file).mtimeMs}` } catch { return `${f.file}:0` } })
    .sort()
    .join('|')
}

// Build (or return cached) { index, availableLangs }.
//   index[scope][lang] = { key: value, ... }
//   availableLangs[scope] = Set(langs)
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

// Short hash of the current on-disk locale set — folded into the catalog
// `version` so clients cache-bust when translations change.
export function localesSignature() {
  return crypto.createHash('sha1').update(build().sig).digest('hex').slice(0, 12)
}

// Scopes that ship at least one locale file, always including 'core' first.
export function listScopes() {
  const { index } = build()
  const scopes = Object.keys(index).filter(s => s !== 'core').sort()
  return ['core', ...scopes]
}

// Languages a scope ships on disk, sorted (BASE_LANG first if present).
export function availableLangs(scope) {
  const set = build().availableLangs[scope]
  if (!set) return []
  return [...set].sort((a, b) => (a === BASE_LANG ? -1 : b === BASE_LANG ? 1 : a.localeCompare(b)))
}

// The language a given scope actually renders in. It's the requested `lang`
// only when that language is enabled for the scope in the admin matrix;
// otherwise the scope falls back to the base (untranslated) language — i.e.
// disabling a language for an app in Admin makes that app render in English.
// When `enabledByScope` is null the gate is off and every scope uses `lang`
// (legacy behaviour, and what non-catalog callers get).
function effectiveLang(scope, lang, enabledByScope) {
  if (lang === BASE_LANG || !enabledByScope) return lang
  const enabled = enabledByScope[scope] || []
  return enabled.includes(lang) ? lang : BASE_LANG
}

// Resolve the flat, ready-to-use message map for an app's client: merges the
// 'core' scope with the app's own scope, applying overrides then the per-key
// fallback chain: override[lang] → base[lang] → override[en] → base[en] → key.
// `ov` is { [lang]: { key: value } } and need only contain `lang` + BASE_LANG.
// `enabledByScope` ({ scope: [langs] }) gates translation per scope: a scope
// whose requested language isn't enabled resolves to BASE_LANG instead.
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

    // Include override-only keys that belong to this scope but aren't in any
    // shipped file (an admin can override a key before it's added to disk).
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

// Completeness of `lang` for `scope` vs the BASE_LANG key set.
export function completeness(scope, lang) {
  const byLang = build().index[scope] || {}
  const base = byLang[BASE_LANG] || {}
  const loc = byLang[lang] || {}
  const baseKeys = Object.keys(base)
  const missingKeys = baseKeys.filter(k => !(k in loc))
  return { total: baseKeys.length, missing: missingKeys.length, missingKeys }
}

// For the override editor: every base key in a scope with its shipped English
// value, the shipped value in `lang`, and whether it differs.
export function scopeKeys(scope, lang) {
  const byLang = build().index[scope] || {}
  const base = byLang[BASE_LANG] || {}
  const loc = byLang[lang] || {}
  return Object.keys(base).sort().map(key => ({ key, base: base[key], value: loc[key] ?? null }))
}
