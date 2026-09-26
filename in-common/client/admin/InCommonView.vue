<script setup>
import { ref, onMounted } from 'vue'
import { Icon } from '@core/icons'

const OPTIONS = [
  {
    value: 'network',
    label: 'Whole network',
    desc: 'Match against everyone on this Nucleus. Best for a household or a close circle where sharing is the point.',
    icon: 'home',
  },
  {
    value: 'group',
    label: 'My group only',
    desc: 'Only match people who share a group with the viewer. Nobody learns about libraries outside their own group.',
    icon: 'users',
  },
]

const scope = ref('network')
const loading = ref(true)
const error = ref(null)
const saving = ref(null)

const j = (url, opts) =>
  fetch(url, { credentials: 'include', ...opts }).then(async (r) => {
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error || `HTTP ${r.status}`)
    return r.json()
  })

async function load() {
  loading.value = true
  error.value = null
  try {
    const data = await j('/api/auth/in-common/config')
    scope.value = data.scope === 'group' ? 'group' : 'network'
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
onMounted(load)

async function choose(value) {
  if (value === scope.value || saving.value) return
  saving.value = value
  error.value = null
  const prev = scope.value
  try {
    const data = await j('/api/auth/in-common/config', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ scope: value }),
    })
    scope.value = data.scope
  } catch (e) {
    scope.value = prev
    error.value = e.message
  } finally {
    saving.value = null
  }
}
</script>

<template>
  <section>
    <h1 class="text-[22px] font-bold text-slate-900 dark:text-white">In Common</h1>
    <p class="text-[13px] text-slate-500 dark:text-white/45 mt-0.5 mb-3">
      Where Watchlist and Shelf look for people who have the same item
    </p>

    <div class="mb-4 flex items-start gap-2.5 rounded-xl bg-indigo-500/10 border border-indigo-500/25 px-3.5 py-2.5">
      <Icon name="info" class="w-4 h-4 mt-0.5 shrink-0 text-indigo-500" />
      <p class="text-xs text-indigo-700 dark:text-indigo-300 leading-relaxed">
        This scope applies to <strong>everyone</strong>. The badge only ever reveals people already in scope, and never the viewer themselves.
      </p>
    </div>

    <p v-if="loading" class="text-sm text-slate-500 dark:text-white/45 py-8 text-center">Loading…</p>
    <p v-else-if="error" class="text-sm text-red-500 py-3">{{ error }}</p>

    <div v-else class="grid gap-2.5 sm:grid-cols-2">
      <button
        v-for="opt in OPTIONS"
        :key="opt.value"
        type="button"
        :disabled="saving"
        @click="choose(opt.value)"
        class="text-left rounded-2xl border px-4 py-3.5 transition-all disabled:opacity-60"
        :class="scope === opt.value
          ? 'border-indigo-500 bg-indigo-500/10 ring-1 ring-indigo-500/40'
          : 'border-slate-200 dark:border-white/10 hover:border-indigo-400/60 bg-white/40 dark:bg-white/5'"
      >
        <div class="flex items-center gap-2.5">
          <Icon :name="opt.icon" class="w-5 h-5 shrink-0"
            :class="scope === opt.value ? 'text-indigo-500' : 'text-slate-400 dark:text-white/40'" />
          <span class="font-semibold text-sm text-slate-900 dark:text-white">{{ opt.label }}</span>
          <span v-if="scope === opt.value" class="ml-auto text-[11px] font-bold uppercase tracking-wide text-indigo-500">Active</span>
          <span v-else-if="saving === opt.value" class="ml-auto text-[11px] text-slate-400">Saving…</span>
        </div>
        <p class="text-xs text-slate-500 dark:text-white/45 mt-1.5 leading-relaxed">{{ opt.desc }}</p>
      </button>
    </div>
  </section>
</template>
