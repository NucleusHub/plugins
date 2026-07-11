<script setup>
import { ref, computed, reactive, onMounted } from 'vue'

// Admin control for the platform-wide maintenance banner. Presets (and a custom
// message) are translated per installed language; raising the banner writes the
// static flag file that nginx serves at /maintenance.json, so it keeps showing
// — already translated — even while the app servers are being rebuilt. See
// core/auth-server/routes/maintenance.js and core/MaintenanceBanner.vue.

const status = ref(null)
const loading = ref(true)
const error = ref(null)
const busy = ref(false)

const j = (url, opts) => fetch(url, { credentials: 'include', ...opts })
  .then(async r => { if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`); return r.json() })

const langLabel = (tag) => {
  try { return new Intl.DisplayNames([tag], { type: 'language' }).of(tag.split('-')[0]) || tag }
  catch { return tag }
}

const langs = computed(() => status.value?.installedLanguages || ['en-US'])
const baseLang = computed(() => status.value?.defaultLanguage || 'en-US')

// Language currently shown in the translation editors (shared across them).
const editLang = ref('en-US')

// ── Raise-banner form ─────────────────────────────────────────────────────────
const mode = ref('preset')          // 'preset' | 'custom'
const selectedPreset = ref('')
const eta = ref('')
const custom = reactive({ title: {}, message: {} })

function fmtEta(raw) {
  const s = String(raw ?? '').trim()
  if (!s) return 'a few minutes'
  if (/^[0-9]+$/.test(s)) return `~${s} min`
  return s
}
const fillEta = (tpl, e) => String(tpl ?? '').replace(/\{eta\}/g, e).replace(/%ETA%/g, e)

const activePreset = computed(() => status.value?.presets.find(p => p.key === selectedPreset.value) || null)

// Live preview of what the banner will say in the editor language.
const preview = computed(() => {
  const e = fmtEta(eta.value)
  const src = mode.value === 'custom' ? custom : activePreset.value
  if (!src) return { title: '', message: '' }
  const pick = (m) => m?.[editLang.value] || m?.[baseLang.value] || Object.values(m || {})[0] || ''
  return { title: fillEta(pick(src.title), e), message: fillEta(pick(src.message), e) }
})

async function load() {
  loading.value = true
  error.value = null
  try {
    status.value = await j('/api/auth/maintenance/status')
    if (!langs.value.includes(editLang.value)) editLang.value = baseLang.value
    if (!selectedPreset.value) selectedPreset.value = status.value.presets[0]?.key || ''
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

async function turnOn() {
  if (busy.value) return
  busy.value = true
  error.value = null
  try {
    const body = mode.value === 'custom'
      ? { eta: eta.value, custom: { title: custom.title, message: custom.message } }
      : { eta: eta.value, preset: selectedPreset.value }
    await j('/api/auth/maintenance/on', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

async function turnOff() {
  if (busy.value) return
  busy.value = true
  error.value = null
  try {
    await j('/api/auth/maintenance/off', { method: 'POST' })
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

// ── Preset editor ─────────────────────────────────────────────────────────────
// `draft` is the preset being edited/created; null when the editor is closed.
const draft = ref(null)
const isNew = computed(() => draft.value && !draft.value._id)

function openEdit(p) {
  draft.value = { _id: p._id, key: p.key, builtin: p.builtin, title: { ...p.title }, message: { ...p.message } }
}
function openNew() {
  draft.value = { key: '', builtin: false, title: {}, message: {} }
}
function closeEdit() { draft.value = null }

async function saveDraft() {
  if (busy.value || !draft.value) return
  busy.value = true
  error.value = null
  try {
    const body = { key: draft.value.key, title: draft.value.title, message: draft.value.message }
    if (isNew.value) {
      await j('/api/auth/maintenance/presets', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    } else {
      await j(`/api/auth/maintenance/presets/${draft.value._id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    }
    closeEdit()
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

async function deletePreset(p) {
  if (busy.value || p.builtin) return
  if (!confirm(`Delete the “${p.key}” preset?`)) return
  busy.value = true
  error.value = null
  try {
    await j(`/api/auth/maintenance/presets/${p._id}`, { method: 'DELETE' })
    if (selectedPreset.value === p.key) selectedPreset.value = ''
    closeEdit()
    await load()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

const presetTitle = (p) => p.title?.[baseLang.value] || p.title?.['en-US'] || Object.values(p.title || {})[0] || p.key
</script>

<template>
  <div class="flex flex-col gap-6">
    <div>
      <h1 class="text-lg font-bold text-slate-900 dark:text-white">Maintenance</h1>
      <p class="text-sm text-slate-500 dark:text-white/50 mt-0.5">Raise a platform-wide banner before an update or rebuild. Messages are translated per language and keep showing while the servers restart.</p>
    </div>

    <p v-if="loading" class="text-sm text-slate-500 dark:text-white/45 py-8 text-center">Loading…</p>
    <p v-else-if="error" class="text-sm text-red-500 py-3 px-4 rounded-xl bg-red-500/10">{{ error }}</p>

    <template v-if="status">
      <!-- Current state -->
      <section
        class="rounded-2xl border p-5"
        :class="status.active
          ? 'bg-amber-500/10 border-amber-500/40'
          : 'bg-white/60 dark:bg-white/[0.04] border-white/70 dark:border-white/10'"
      >
        <div class="flex items-center gap-3 flex-wrap">
          <span
            class="inline-flex items-center gap-2 text-sm font-bold"
            :class="status.active ? 'text-amber-700 dark:text-amber-300' : 'text-emerald-600 dark:text-emerald-400'"
          >
            <span class="w-2.5 h-2.5 rounded-full" :class="status.active ? 'bg-amber-500 animate-pulse' : 'bg-emerald-500'" />
            {{ status.active ? 'Maintenance banner is ACTIVE' : 'Banner is off' }}
          </span>
          <div class="flex-1" />
          <button
            v-if="status.active"
            class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-emerald-600 hover:bg-emerald-500 disabled:opacity-50 cursor-pointer transition-colors"
            :disabled="busy"
            @click="turnOff"
          >Turn off</button>
        </div>
        <div v-if="status.active && status.current" class="mt-3 text-sm text-amber-900/90 dark:text-amber-100/80">
          <p class="font-semibold">{{ status.current.title?.[baseLang] || status.current.title?.['en-US'] }}</p>
          <p class="opacity-80">{{ status.current.message?.[baseLang] || status.current.message?.['en-US'] }}</p>
          <p class="text-[11px] opacity-60 mt-1">
            Preset: {{ status.current.preset }}<template v-if="status.current.eta"> · ETA {{ status.current.eta }}</template><template v-if="status.current.since"> · since {{ new Date(status.current.since).toLocaleString() }}</template>
          </p>
        </div>
      </section>

      <!-- Raise the banner -->
      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35 mb-3">Raise the banner</h2>

        <div class="flex gap-1 bg-black/5 dark:bg-white/8 rounded-xl p-1 w-max mb-4">
          <button
            v-for="m in ['preset', 'custom']" :key="m"
            class="px-3 py-1 rounded-lg text-xs font-semibold capitalize cursor-pointer transition-colors"
            :class="mode === m ? 'bg-white dark:bg-white/20 text-indigo-600 dark:text-indigo-300 shadow-sm' : 'text-slate-500 dark:text-white/50 hover:text-slate-800 dark:hover:text-white'"
            @click="mode = m"
          >{{ m === 'preset' ? 'Preset' : 'Custom message' }}</button>
        </div>

        <div class="flex flex-wrap items-end gap-3 mb-4">
          <label v-if="mode === 'preset'" class="flex flex-col gap-1">
            <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">Preset</span>
            <select v-model="selectedPreset" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 cursor-pointer">
              <option v-for="p in status.presets" :key="p.key" :value="p.key">{{ presetTitle(p) }} ({{ p.key }})</option>
            </select>
          </label>
          <label class="flex flex-col gap-1">
            <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">ETA <span class="font-normal opacity-60">(e.g. 5 or “1 hour”)</span></span>
            <input v-model="eta" placeholder="a few minutes" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 w-40" />
          </label>
        </div>

        <!-- Custom-message translation editor -->
        <div v-if="mode === 'custom'" class="mb-4">
          <div class="flex gap-1 bg-black/5 dark:bg-white/8 rounded-xl p-1 w-max mb-3">
            <button
              v-for="l in langs" :key="l"
              class="px-3 py-1 rounded-lg text-xs font-semibold cursor-pointer transition-colors"
              :class="editLang === l ? 'bg-white dark:bg-white/20 text-indigo-600 dark:text-indigo-300 shadow-sm' : 'text-slate-500 dark:text-white/50 hover:text-slate-800 dark:hover:text-white'"
              @click="editLang = l"
            >{{ l }}</button>
          </div>
          <div class="flex flex-col gap-2">
            <input v-model="custom.title[editLang]" :placeholder="`Title (${langLabel(editLang)})`" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2" />
            <textarea v-model="custom.message[editLang]" rows="2" :placeholder="`Message (${langLabel(editLang)}) — use {eta} for the duration`" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 resize-y" />
          </div>
        </div>

        <!-- Preview -->
        <div class="rounded-xl bg-amber-500/10 border border-amber-500/30 px-4 py-3 mb-4">
          <p class="text-[10px] font-bold uppercase tracking-wider text-amber-700/70 dark:text-amber-300/60 mb-1">Preview · {{ editLang }}</p>
          <p class="text-sm font-bold text-amber-900 dark:text-amber-200">{{ preview.title || '—' }}</p>
          <p class="text-xs text-amber-900/80 dark:text-amber-200/80">{{ preview.message || '—' }}</p>
        </div>

        <button
          class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-amber-600 hover:bg-amber-500 disabled:opacity-50 cursor-pointer transition-colors"
          :disabled="busy || (mode === 'preset' && !selectedPreset) || (mode === 'custom' && !preview.message)"
          @click="turnOn"
        >{{ status.active ? 'Update banner' : 'Turn on banner' }}</button>
      </section>

      <!-- Presets -->
      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">Presets</h2>
          <button class="text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer" @click="openNew">+ New preset</button>
        </div>

        <ul class="flex flex-col divide-y divide-slate-200/60 dark:divide-white/8">
          <li v-for="p in status.presets" :key="p._id" class="flex items-center gap-3 py-2.5">
            <div class="flex-1 min-w-0">
              <span class="text-sm font-medium text-slate-900 dark:text-white">{{ presetTitle(p) }}</span>
              <span class="ml-1.5 text-xs text-slate-400 dark:text-white/40">{{ p.key }}</span>
              <span v-if="p.builtin" class="ml-2 text-[10px] font-semibold text-indigo-600 dark:text-indigo-300 bg-indigo-500/10 px-1.5 py-0.5 rounded">Built-in</span>
            </div>
            <button class="px-3 py-1.5 rounded-lg text-xs font-semibold text-indigo-600 dark:text-indigo-300 bg-indigo-500/10 hover:bg-indigo-500/20 cursor-pointer transition-colors" @click="openEdit(p)">Edit</button>
            <button
              class="px-3 py-1.5 rounded-lg text-xs font-semibold text-red-600 dark:text-red-400 bg-red-500/12 hover:bg-red-500/22 cursor-pointer transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="busy || p.builtin"
              :title="p.builtin ? 'Built-in presets can’t be deleted' : ''"
              @click="deletePreset(p)"
            >Delete</button>
          </li>
        </ul>

        <!-- Inline editor -->
        <div v-if="draft" class="mt-4 rounded-xl border border-indigo-500/30 bg-indigo-500/[0.04] p-4 flex flex-col gap-3">
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-bold text-slate-900 dark:text-white">{{ isNew ? 'New preset' : `Edit “${draft.key}”` }}</h3>
            <button class="text-xs text-slate-400 hover:text-slate-600 dark:hover:text-white cursor-pointer" @click="closeEdit">Cancel</button>
          </div>

          <label class="flex flex-col gap-1">
            <span class="text-[11px] font-semibold text-slate-500 dark:text-white/50">Key</span>
            <input
              v-model="draft.key"
              :disabled="draft.builtin"
              placeholder="e.g. hotfix"
              class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 w-52 disabled:opacity-50"
            />
            <span v-if="draft.builtin" class="text-[10px] text-slate-400 dark:text-white/35">Built-in key can’t be changed.</span>
          </label>

          <div class="flex gap-1 bg-black/5 dark:bg-white/8 rounded-xl p-1 w-max">
            <button
              v-for="l in langs" :key="l"
              class="px-3 py-1 rounded-lg text-xs font-semibold cursor-pointer transition-colors"
              :class="editLang === l ? 'bg-white dark:bg-white/20 text-indigo-600 dark:text-indigo-300 shadow-sm' : 'text-slate-500 dark:text-white/50 hover:text-slate-800 dark:hover:text-white'"
              @click="editLang = l"
            >{{ l }}<span v-if="l === baseLang" class="ml-1 opacity-50">·base</span></button>
          </div>

          <div class="flex flex-col gap-2">
            <input v-model="draft.title[editLang]" :placeholder="`Title (${langLabel(editLang)})`" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2" />
            <textarea v-model="draft.message[editLang]" rows="3" :placeholder="`Message (${langLabel(editLang)}) — use {eta} for the duration`" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 resize-y" />
          </div>
          <p class="text-[11px] text-slate-400 dark:text-white/35">The {{ baseLang }} message is required; other languages fall back to it when empty.</p>

          <div>
            <button
              class="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 cursor-pointer transition-colors"
              :disabled="busy"
              @click="saveDraft"
            >Save preset</button>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
