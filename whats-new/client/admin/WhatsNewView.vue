<script setup>
import { ref, computed, onMounted } from 'vue'
import WhatsNewDeleteModal from './WhatsNewDeleteModal.vue'
import WhatsNewModalView from '../WhatsNewModalView.vue'

const data = ref(null)
const appOptions = ref([])
const platformVersion = ref('')
const loading = ref(true)
const error = ref(null)
const busy = ref(false)

const j = (url, opts) => fetch(url, { credentials: 'include', ...opts })
  .then(async r => { if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`); return r.json() })

const langLabel = (tag) => {
  try { return new Intl.DisplayNames([tag], { type: 'language' }).of(tag.split('-')[0]) || tag }
  catch { return tag }
}

const langs = computed(() => data.value?.installedLanguages || ['en-US'])
const baseLang = computed(() => data.value?.defaultLanguage || 'en-US')
const editLang = ref('en-US')

const appName = (id) => appOptions.value.find(a => a.id === id)?.name || id
const versionFor = (id) => appOptions.value.find(a => a.id === id)?.version || ''

async function load() {
  loading.value = true
  error.value = null
  try {
    data.value = await j('/api/auth/whats-new/announcements')
    if (!langs.value.includes(editLang.value)) editLang.value = baseLang.value
    const [apps, nucleus] = await Promise.all([
      fetch('/api/registry/apps', { credentials: 'include' }).then(r => r.ok ? r.json() : []).catch(() => []),
      fetch('/api/registry/nucleus', { credentials: 'include' }).then(r => r.ok ? r.json() : {}).catch(() => ({})),
    ])
    platformVersion.value = nucleus.version || ''
    appOptions.value = [
      { id: 'platform', name: 'Platform (general)', version: platformVersion.value },
      ...apps.map(a => ({ id: a.id, name: a.name || a.id, version: a.version || '' })),
    ]
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

const draft = ref(null)
const isNew = computed(() => draft.value && !draft.value._id)

const emptyFeature = () => ({ title: {}, body: {}, icon: '' })
const emptyEntry = (appId = 'platform') => ({ app: appId, version: versionFor(appId), features: [emptyFeature()] })

function openNew() {
  draft.value = { version: platformVersion.value, entries: [emptyEntry('platform')] }
}
function openEdit(a) {
  draft.value = {
    _id: a._id,
    version: a.version,
    entries: (a.entries || []).map(e => ({
      app: e.app,
      version: e.version || '',
      features: (e.features || []).map(f => ({ title: { ...f.title }, body: { ...f.body }, icon: f.icon || '' })),
    })),
  }
  if (!draft.value.entries.length) draft.value.entries.push(emptyEntry())
}
function closeEdit() { draft.value = null }

const importOpen = ref(false)
const importText = ref('')
const importError = ref(null)

function openImport() {
  importText.value = ''
  importError.value = null
  importOpen.value = true
}
function closeImport() { importOpen.value = false }

function onImportFile(e) {
  const file = e.target.files?.[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = () => { importText.value = String(reader.result || '') }
  reader.onerror = () => { importError.value = 'Could not read the file' }
  reader.readAsText(file)
  e.target.value = ''
}

function normalizeImported(obj) {
  const langMap = (m) => (m && typeof m === 'object' && !Array.isArray(m))
    ? Object.fromEntries(Object.entries(m).filter(([, v]) => typeof v === 'string'))
    : {}
  const entries = Array.isArray(obj?.entries) ? obj.entries : []
  return {
    version: String(obj?.version || '').trim(),
    entries: entries
      .filter(e => e && typeof e.app === 'string' && e.app.trim())
      .map(e => ({
        app: e.app.trim(),
        version: String(e.version || '').trim(),
        features: (Array.isArray(e.features) ? e.features : []).map(f => ({
          icon: f?.icon ? String(f.icon).slice(0, 4) : '',
          title: langMap(f?.title),
          body: langMap(f?.body),
        })),
      })),
  }
}

function applyImport() {
  importError.value = null
  let parsed
  try {
    parsed = JSON.parse(importText.value)
  } catch (e) {
    importError.value = `Invalid JSON: ${e.message}`
    return
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    importError.value = 'Expected a JSON object with "version" and "entries".'
    return
  }
  const normalized = normalizeImported(parsed)
  if (!normalized.version) { importError.value = 'The JSON is missing a "version" string.'; return }
  if (!normalized.entries.length) { importError.value = 'The JSON has no valid entries (each needs an "app").'; return }
  const known = new Set(appOptions.value.map(a => a.id))
  const unknown = [...new Set(normalized.entries.map(e => e.app).filter(a => !known.has(a)))]
  draft.value = { version: normalized.version, entries: normalized.entries }
  draft.value.entries.forEach(e => { if (!e.features.length) e.features.push(emptyFeature()) })
  importOpen.value = false
  if (unknown.length) error.value = `Imported. Note: unknown app id(s) — ${unknown.join(', ')}. Fix the tab(s) before saving.`
}

function addEntry() { draft.value.entries.push(emptyEntry()) }
function removeEntry(i) { draft.value.entries.splice(i, 1) }
function onEntryApp(entry) { entry.version = versionFor(entry.app) }
function addFeature(entry) { entry.features.push(emptyFeature()) }
function removeFeature(entry, i) { entry.features.splice(i, 1) }

async function saveDraft() {
  if (busy.value || !draft.value) return
  if (!draft.value.version.trim()) { error.value = 'A version label is required'; return }
  busy.value = true
  error.value = null
  try {
    const body = { version: draft.value.version, entries: draft.value.entries }
    if (isNew.value) {
      await j('/api/auth/whats-new/announcements', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    } else {
      await j(`/api/auth/whats-new/announcements/${draft.value._id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    }
    closeEdit()
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

async function setPublished(a, published) {
  if (busy.value) return
  busy.value = true
  error.value = null
  try {
    await j(`/api/auth/whats-new/announcements/${a._id}/${published ? 'publish' : 'unpublish'}`, { method: 'POST' })
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

const deleteTarget = ref(null)
function askDelete(a) { if (!busy.value) deleteTarget.value = a }
async function onDeleted() {
  deleteTarget.value = null
  closeEdit()
  await load()
}

const fmtDate = (d) => d ? new Date(d).toLocaleDateString() : ''

const previewOpen = ref(false)
const previewFeed = ref([])

function preview(src) {
  const a = src || draft.value
  if (!a) return
  previewFeed.value = [{
    _id: a._id || 'preview',
    version: a.version || '',
    published: true,
    publishedAt: new Date().toISOString(),
    entries: (a.entries || []).map(e => ({
      app: e.app,
      version: e.version || '',
      features: (e.features || []).map(f => ({
        title: { ...(f.title || {}) },
        body: { ...(f.body || {}) },
        icon: f.icon || null,
      })),
    })),
  }]
  previewOpen.value = true
}
</script>

<template>
  <div class="flex flex-col gap-6">
    <div>
      <h1 class="text-lg font-bold text-slate-900 dark:text-white">What's New</h1>
      <p class="text-sm text-slate-500 dark:text-white/50 mt-0.5">Author release notes shown to users on login. Group features by app (they become tabs) and translate each per language. Publishing a new announcement pops the changelog for everyone once.</p>
    </div>

    <p v-if="loading" class="text-sm text-slate-500 dark:text-white/45 py-8 text-center">Loading…</p>
    <p v-else-if="error" class="text-sm text-red-500 py-3 px-4 rounded-xl bg-red-500/10">{{ error }}</p>

    <template v-if="data">
      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">Announcements</h2>
          <div class="flex items-center gap-4">
            <button class="text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer" @click="openImport">↥ Import JSON</button>
            <button class="text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer" @click="openNew">+ New announcement</button>
          </div>
        </div>

        <div v-if="importOpen" class="mb-4 rounded-xl border border-indigo-500/30 bg-indigo-500/[0.04] p-4 flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-bold text-slate-900 dark:text-white">Import announcement from JSON</h3>
            <button class="text-xs text-slate-400 hover:text-slate-600 dark:hover:text-white cursor-pointer" @click="closeImport">Cancel</button>
          </div>
          <p class="text-[11px] text-slate-500 dark:text-white/45">Paste a generated JSON announcement (or load a <code>.json</code> file). It opens in the editor below for review — nothing is saved until you hit “Save announcement”. See the docs for the schema.</p>
          <label class="self-start text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer">
            Load .json file…
            <input type="file" accept="application/json,.json" class="hidden" @change="onImportFile" />
          </label>
          <textarea
            v-model="importText"
            rows="10"
            spellcheck="false"
            placeholder='{
  "version": "0.4.0",
  "entries": [
    {
      "app": "orbit",
      "version": "0.2.1",
      "features": [
        { "icon": "✨", "title": { "en-US": "Faster uploads" }, "body": { "en-US": "Big files fly now." } }
      ]
    }
  ]
}'
            class="text-xs font-mono rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 resize-y"
          />
          <p v-if="importError" class="text-xs text-red-500">{{ importError }}</p>
          <div>
            <button class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 cursor-pointer transition-colors" :disabled="!importText.trim()" @click="applyImport">Load into editor</button>
          </div>
        </div>

        <p v-if="!data.announcements.length" class="text-sm text-slate-400 dark:text-white/40 py-4 text-center">No announcements yet.</p>

        <ul v-else class="flex flex-col divide-y divide-slate-200/60 dark:divide-white/8">
          <li v-for="a in data.announcements" :key="a._id" class="flex items-center gap-3 py-2.5">
            <div class="flex-1 min-w-0">
              <span class="text-sm font-semibold text-slate-900 dark:text-white">{{ a.version }}</span>
              <span
                class="ml-2 text-[10px] font-semibold px-1.5 py-0.5 rounded"
                :class="a.published ? 'text-emerald-600 dark:text-emerald-300 bg-emerald-500/10' : 'text-slate-500 dark:text-white/45 bg-slate-500/10'"
              >{{ a.published ? 'Published' : 'Draft' }}</span>
              <span v-if="a.publishedAt" class="ml-2 text-xs text-slate-400 dark:text-white/40">{{ fmtDate(a.publishedAt) }}</span>
              <span class="ml-2 text-xs text-slate-400 dark:text-white/40">· {{ a.entries.length }} {{ a.entries.length === 1 ? 'app' : 'apps' }}</span>
            </div>
            <button
              class="px-3 py-1.5 rounded-lg text-xs font-semibold cursor-pointer transition-colors"
              :class="a.published
                ? 'text-amber-600 dark:text-amber-300 bg-amber-500/12 hover:bg-amber-500/22'
                : 'text-emerald-600 dark:text-emerald-300 bg-emerald-500/12 hover:bg-emerald-500/22'"
              :disabled="busy"
              @click="setPublished(a, !a.published)"
            >{{ a.published ? 'Unpublish' : 'Publish' }}</button>
            <button class="px-3 py-1.5 rounded-lg text-xs font-semibold text-slate-600 dark:text-white/70 bg-slate-500/10 hover:bg-slate-500/20 cursor-pointer transition-colors" @click="preview(a)" title="See how this looks to users">Preview</button>
            <button class="px-3 py-1.5 rounded-lg text-xs font-semibold text-indigo-600 dark:text-indigo-300 bg-indigo-500/10 hover:bg-indigo-500/20 cursor-pointer transition-colors" @click="openEdit(a)">Edit</button>
            <button class="px-3 py-1.5 rounded-lg text-xs font-semibold text-red-600 dark:text-red-400 bg-red-500/12 hover:bg-red-500/22 cursor-pointer transition-colors disabled:opacity-40" :disabled="busy" @click="askDelete(a)">Delete</button>
          </li>
        </ul>

        <div v-if="draft" class="mt-4 rounded-xl border border-indigo-500/30 bg-indigo-500/[0.04] p-4 flex flex-col gap-4">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-bold text-slate-900 dark:text-white">{{ isNew ? 'New announcement' : `Edit “${draft.version}”` }}</h3>
            <button class="text-xs text-slate-400 hover:text-slate-600 dark:hover:text-white cursor-pointer" @click="closeEdit">Cancel</button>
          </div>

          <div class="flex flex-wrap items-end gap-3">
            <label class="flex flex-col gap-1">
              <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">Nucleus version <span class="font-normal opacity-60">(whole platform)</span></span>
              <input v-model="draft.version" :placeholder="platformVersion || 'e.g. 0.4.0'" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 w-40" />
            </label>
            <div class="flex gap-1 bg-black/5 dark:bg-white/8 rounded-xl p-1 w-max">
              <button
                v-for="l in langs" :key="l"
                class="px-3 py-1 rounded-lg text-xs font-semibold cursor-pointer transition-colors"
                :class="editLang === l ? 'bg-white dark:bg-white/20 text-indigo-600 dark:text-indigo-300 shadow-sm' : 'text-slate-500 dark:text-white/50 hover:text-slate-800 dark:hover:text-white'"
                @click="editLang = l"
              >{{ l }}<span v-if="l === baseLang" class="ml-1 opacity-50">·base</span></button>
            </div>
          </div>

          <div v-for="(entry, ei) in draft.entries" :key="ei" class="rounded-xl border border-slate-200/70 dark:border-white/10 bg-white/50 dark:bg-white/[0.02] p-3 flex flex-col gap-3">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">Tab / app</span>
              <select v-model="entry.app" @change="onEntryApp(entry)" class="text-sm rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-2 py-1.5 cursor-pointer">
                <option v-for="opt in appOptions" :key="opt.id" :value="opt.id">{{ opt.name }}</option>
              </select>
              <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">version</span>
              <input v-model="entry.version" :placeholder="versionFor(entry.app) || 'e.g. 0.2.1'" class="text-sm rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-2 py-1.5 w-24" :title="`Version of ${appName(entry.app)} for this release`" />
              <div class="flex-1" />
              <button class="text-xs text-red-500 hover:text-red-600 cursor-pointer" @click="removeEntry(ei)">Remove tab</button>
            </div>

            <div v-for="(f, fi) in entry.features" :key="fi" class="flex gap-2 items-start rounded-lg bg-black/[0.02] dark:bg-white/[0.03] p-2">
              <input v-model="f.icon" maxlength="4" placeholder="✨" class="text-center text-base rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 w-11 py-2 shrink-0" :title="`Optional emoji for “${appName(entry.app)}”`" />
              <div class="flex-1 flex flex-col gap-1.5 min-w-0">
                <input v-model="f.title[editLang]" :placeholder="`Feature title (${langLabel(editLang)})`" class="text-sm rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2" />
                <textarea v-model="f.body[editLang]" rows="2" :placeholder="`Description (${langLabel(editLang)}) — optional`" class="text-sm rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 resize-y" />
              </div>
              <button class="text-xs text-slate-400 hover:text-red-500 cursor-pointer py-2 shrink-0" @click="removeFeature(entry, fi)" title="Remove feature">✕</button>
            </div>

            <button class="self-start text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer" @click="addFeature(entry)">+ Add feature</button>
          </div>

          <button class="self-start text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer" @click="addEntry">+ Add app tab</button>

          <p class="text-[11px] text-slate-400 dark:text-white/35">Fill each language via the tabs above; empty languages fall back to {{ baseLang }} for the viewer. Publish when ready — that's when it pops for users.</p>

          <div class="flex items-center gap-3">
            <button class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 cursor-pointer transition-colors" :disabled="busy" @click="saveDraft">Save announcement</button>
            <button class="px-4 py-2 rounded-xl text-sm font-semibold text-indigo-600 dark:text-indigo-300 bg-indigo-500/10 hover:bg-indigo-500/20 cursor-pointer transition-colors" @click="preview(draft)" title="See how this draft looks to users — nothing is saved">Preview</button>
          </div>
        </div>
      </section>
    </template>

    <WhatsNewModalView
      v-model="previewOpen"
      :announcements="previewFeed"
      :default-lang="baseLang"
      :seen-baseline="null"
      preview
    />

    <WhatsNewDeleteModal
      :announcement="deleteTarget"
      @close="deleteTarget = null"
      @deleted="onDeleted"
    />
  </div>
</template>
