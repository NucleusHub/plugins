<script setup>
import { ref, computed, onMounted } from 'vue'

const overview = ref(null)
const loading = ref(true)
const error = ref(null)
const busy = ref(false)

const selectedLang = ref(null)
const installChoice = ref('')

const j = (url, opts) => fetch(url, { credentials: 'include', ...opts })
  .then(async r => { if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`); return r.json() })

const langLabel = (tag) => {
  try { return new Intl.DisplayNames([tag], { type: 'language' }).of(tag.split('-')[0]) || tag }
  catch { return tag }
}
const scopeLabel = (s) => s === 'core' ? 'Core' : s.charAt(0).toUpperCase() + s.slice(1)

async function loadOverview() {
  loading.value = true
  error.value = null
  try {
    overview.value = await j('/api/auth/i18n/admin/overview')
    if (!selectedLang.value || !overview.value.installedLanguages.includes(selectedLang.value)) {
      selectedLang.value = overview.value.installedLanguages.find(l => l !== 'en-US') || overview.value.installedLanguages[0] || 'en-US'
    }
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(loadOverview)

const notInstalled = computed(() =>
  (overview.value?.installable || []).filter(l => !overview.value.installedLanguages.includes(l)))

const enabledSet = computed(() => new Set(overview.value?.enabledLanguages || []))
const isEnabled = (l) => enabledSet.value.has(l)
const canUninstall = computed(() => (overview.value?.installedLanguages.length || 0) > 1)
const canDisable = computed(() => (overview.value?.enabledLanguages.length || 0) > 1)

async function installLang() {
  if (!installChoice.value || busy.value) return
  busy.value = true
  try { await j('/api/auth/i18n/admin/languages', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ lang: installChoice.value }) }); installChoice.value = ''; await loadOverview() }
  catch (e) { error.value = e.message } finally { busy.value = false }
}

async function uninstallLang(lang) {
  if (busy.value || !canUninstall.value) return
  busy.value = true
  try { await j(`/api/auth/i18n/admin/languages/${lang}`, { method: 'DELETE' }); await loadOverview() }
  catch (e) { error.value = e.message } finally { busy.value = false }
}

async function setLanguageEnabled(lang, enabled) {
  if (busy.value) return
  busy.value = true
  try { await j(`/api/auth/i18n/admin/languages/${lang}/enabled`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled }) }); await loadOverview() }
  catch (e) { error.value = e.message } finally { busy.value = false }
}

async function setDefault(lang) {
  if (busy.value) return
  busy.value = true
  try { await j('/api/auth/i18n/admin/default', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ lang }) }); await loadOverview() }
  catch (e) { error.value = e.message } finally { busy.value = false }
}

const scopeRows = computed(() => (overview.value?.scopes || []).map(s => {
  const available = s.availableLangs.includes(selectedLang.value)
  const enabled = s.enabledLangs.includes(selectedLang.value)
  const comp = s.completeness?.[selectedLang.value]
  return { scope: s.scope, available, enabled, comp }
}))

async function toggleEnabled(scope, enabled) {
  if (busy.value) return
  busy.value = true
  try {
    await j('/api/auth/i18n/admin/enabled', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ lang: selectedLang.value, scope, enabled }) })
    await loadOverview()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}

const ovScope = ref('core')
const ovLang = ref('en-US')
const ovKeys = ref([])
const ovLoading = ref(false)
const ovFilter = ref('')
const drafts = ref({})

async function loadKeys() {
  ovLoading.value = true
  try {
    const data = await j(`/api/auth/i18n/admin/keys?scope=${encodeURIComponent(ovScope.value)}&lang=${encodeURIComponent(ovLang.value)}`)
    ovKeys.value = data.keys
    drafts.value = Object.fromEntries(data.keys.map(k => [k.key, k.override ?? '']))
  } catch (e) { error.value = e.message } finally { ovLoading.value = false }
}

const filteredKeys = computed(() => {
  const q = ovFilter.value.trim().toLowerCase()
  if (!q) return ovKeys.value
  return ovKeys.value.filter(k => k.key.toLowerCase().includes(q) || (k.base || '').toLowerCase().includes(q))
})

async function saveOverride(k) {
  const value = drafts.value[k.key] ?? ''
  busy.value = true
  try {
    if (value === '') { await j('/api/auth/i18n/admin/overrides', { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ lang: ovLang.value, key: k.key }) }) }
    else { await j('/api/auth/i18n/admin/overrides', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ lang: ovLang.value, key: k.key, value }) }) }
    await loadKeys()
  } catch (e) { error.value = e.message } finally { busy.value = false }
}
</script>

<template>
  <div class="flex flex-col gap-6">
    <div>
      <h1 class="text-lg font-bold text-slate-900 dark:text-white">Localization</h1>
      <p class="text-sm text-slate-500 dark:text-white/50 mt-0.5">Install languages, enable them per app, and override translations. Missing translations fall back to English.</p>
    </div>

    <p v-if="loading" class="text-sm text-slate-500 dark:text-white/45 py-8 text-center">Loading…</p>
    <p v-else-if="error" class="text-sm text-red-500 py-3 px-4 rounded-xl bg-red-500/10">{{ error }}</p>

    <template v-if="overview">
      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35 mb-3">Installed languages</h2>
        <ul class="flex flex-col divide-y divide-slate-200/60 dark:divide-white/8">
          <li v-for="l in overview.installedLanguages" :key="l" class="flex items-center gap-3 py-2.5">
            <div class="flex-1 min-w-0">
              <span class="text-sm font-medium text-slate-900 dark:text-white">{{ langLabel(l) }}</span>
              <span class="ml-1.5 text-xs text-slate-400 dark:text-white/40">{{ l }}</span>
              <span v-if="l === overview.defaultLanguage" class="ml-2 text-[10px] font-semibold text-indigo-600 dark:text-indigo-300 bg-indigo-500/10 px-1.5 py-0.5 rounded">Default</span>
            </div>

            <button
              v-if="l !== overview.defaultLanguage"
              class="text-[11px] font-semibold text-indigo-600 dark:text-indigo-300 hover:underline cursor-pointer disabled:opacity-40 disabled:no-underline"
              :disabled="busy"
              title="Make this the instance default language"
              @click="setDefault(l)"
            >Set default</button>

            <span
              class="text-[11px] font-semibold px-2 py-0.5 rounded"
              :class="isEnabled(l) ? 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/10' : 'text-slate-400 dark:text-white/40 bg-slate-500/10 dark:bg-white/8'"
            >{{ isEnabled(l) ? 'Enabled' : 'Disabled' }}</span>

            <button
              class="px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
              :class="isEnabled(l) ? 'text-amber-600 dark:text-amber-400 bg-amber-500/12 hover:bg-amber-500/22' : 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/12 hover:bg-emerald-500/22'"
              :disabled="busy || (isEnabled(l) && !canDisable)"
              :title="isEnabled(l) && !canDisable ? 'At least one language must stay enabled' : ''"
              @click="setLanguageEnabled(l, !isEnabled(l))"
            >{{ isEnabled(l) ? 'Disable' : 'Enable' }}</button>

            <button
              class="px-3 py-1.5 rounded-lg text-xs font-semibold text-red-600 dark:text-red-400 bg-red-500/12 hover:bg-red-500/22 transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="busy || !canUninstall"
              :title="!canUninstall ? 'At least one language must stay installed' : ''"
              @click="uninstallLang(l)"
            >Uninstall</button>
          </li>
        </ul>
        <div v-if="notInstalled.length" class="flex items-center gap-2 mt-4">
          <select v-model="installChoice" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 cursor-pointer">
            <option value="">Add a language…</option>
            <option v-for="l in notInstalled" :key="l" :value="l">{{ langLabel(l) }} ({{ l }})</option>
          </select>
          <button
            class="px-3 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 cursor-pointer transition-colors"
            :disabled="!installChoice || busy"
            @click="installLang"
          >Install</button>
        </div>
        <p v-else-if="!notInstalled.length" class="text-xs text-slate-400 dark:text-white/35 mt-3">Every language shipped on disk is installed. Add locale files under <code>apps/&lt;app&gt;/locales/</code> to offer more.</p>
      </section>

      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <div class="flex items-center justify-between flex-wrap gap-2 mb-3">
          <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">Enable per app</h2>
          <div class="flex gap-1 bg-black/5 dark:bg-white/8 rounded-xl p-1">
            <button
              v-for="l in overview.installedLanguages"
              :key="l"
              class="px-3 py-1 rounded-lg text-xs font-semibold cursor-pointer transition-colors"
              :class="selectedLang === l ? 'bg-white dark:bg-white/20 text-indigo-600 dark:text-indigo-300 shadow-sm' : 'text-slate-500 dark:text-white/50 hover:text-slate-800 dark:hover:text-white'"
              @click="selectedLang = l"
            >{{ l }}</button>
          </div>
        </div>

        <ul class="flex flex-col divide-y divide-slate-200/60 dark:divide-white/8">
          <li v-for="row in scopeRows" :key="row.scope" class="flex items-center gap-3 py-2.5">
            <span class="text-sm font-medium text-slate-900 dark:text-white flex-1">{{ scopeLabel(row.scope) }}</span>

            <span v-if="!row.available" class="text-[11px] font-medium text-amber-600 dark:text-amber-400">⚠ Unavailable · fallback English</span>
            <span v-else-if="row.comp && row.comp.missing === 0" class="text-[11px] font-medium text-emerald-600 dark:text-emerald-400">✓ Complete</span>
            <span v-else-if="row.comp" class="text-[11px] font-medium text-amber-600 dark:text-amber-400">⚠ Missing {{ row.comp.missing }} of {{ row.comp.total }}</span>

            <span v-if="selectedLang === 'en-US'" class="shrink-0 text-[11px] font-semibold text-slate-500 dark:text-white/50 bg-slate-500/10 dark:bg-white/10 px-2 py-1 rounded-lg">Base</span>
            <button
              v-else-if="row.available"
              class="shrink-0 px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer disabled:opacity-50"
              :class="row.enabled ? 'text-red-600 dark:text-red-400 bg-red-500/12 hover:bg-red-500/22' : 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/12 hover:bg-emerald-500/22'"
              :disabled="busy"
              @click="toggleEnabled(row.scope, !row.enabled)"
            >{{ row.enabled ? 'Disable' : 'Enable' }}</button>
            <span v-else class="shrink-0 text-[11px] text-slate-400 dark:text-white/35">can’t enable</span>
          </li>
        </ul>
      </section>

      <section class="rounded-2xl bg-white/60 dark:bg-white/[0.04] border border-white/70 dark:border-white/10 p-5">
        <h2 class="text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35 mb-3">Translation overrides</h2>
        <div class="flex flex-wrap items-center gap-2 mb-3">
          <select v-model="ovScope" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 cursor-pointer">
            <option v-for="s in overview.scopes" :key="s.scope" :value="s.scope">{{ scopeLabel(s.scope) }}</option>
          </select>
          <select v-model="ovLang" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 cursor-pointer">
            <option v-for="l in overview.installedLanguages" :key="l" :value="l">{{ l }}</option>
          </select>
          <button class="px-3 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 cursor-pointer transition-colors" @click="loadKeys">Load keys</button>
          <input v-if="ovKeys.length" v-model="ovFilter" placeholder="Filter…" class="text-sm rounded-xl border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-3 py-2 flex-1 min-w-[8rem]" />
        </div>

        <p v-if="ovLoading" class="text-sm text-slate-500 dark:text-white/45 py-4 text-center">Loading…</p>
        <p v-else-if="!ovKeys.length" class="text-xs text-slate-400 dark:text-white/35">Pick a scope and language, then <strong>Load keys</strong> to edit.</p>
        <ul v-else class="flex flex-col gap-2 max-h-[28rem] overflow-y-auto">
          <li v-for="k in filteredKeys" :key="k.key" class="flex flex-col gap-1 p-2.5 rounded-xl bg-black/[0.03] dark:bg-white/[0.03]">
            <div class="flex items-center gap-2">
              <code class="text-[11px] text-indigo-600 dark:text-indigo-300 font-semibold">{{ k.key }}</code>
              <span v-if="k.override != null" class="text-[10px] font-semibold text-amber-600 dark:text-amber-400 bg-amber-500/10 px-1.5 py-0.5 rounded">overridden</span>
            </div>
            <p class="text-[11px] text-slate-400 dark:text-white/40 truncate">en-US: {{ k.base }}<template v-if="ovLang !== 'en-US' && k.value != null"> · {{ ovLang }}: {{ k.value }}</template></p>
            <div class="flex items-center gap-2">
              <input v-model="drafts[k.key]" :placeholder="k.value ?? k.base" class="flex-1 text-sm rounded-lg border border-slate-300 dark:border-white/15 bg-white/70 dark:bg-white/5 text-slate-900 dark:text-white px-2.5 py-1.5" @keydown.enter.prevent="saveOverride(k)" />
              <button class="shrink-0 px-2.5 py-1.5 rounded-lg text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 cursor-pointer transition-colors" :disabled="busy" @click="saveOverride(k)">Save</button>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
