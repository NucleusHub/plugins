<script setup>
import { ref, computed, watch } from 'vue'
import PersonPhoto from './PersonPhoto.vue'

const props = defineProps({
  arg: { type: String, required: true },
  host: { type: Object, required: true },
})

const credits = ref(null)
const tab = ref('cast')

const parts = computed(() => {
  const [kind, id, ...title] = props.arg.split(':')
  return { kind, tmdbID: Number(id), title: title.join(':') }
})

watch(parts, async ({ kind, tmdbID }) => {
  credits.value = null
  if (!(kind === 'movie' || kind === 'show') || !tmdbID) return
  credits.value = await props.host.credits(kind, tmdbID).catch(() => ({ cast: [], crew: [] }))
}, { immediate: true })

// Departments in the order TMDb's ranking first brings them up.
const departments = computed(() => {
  const groups = new Map()
  for (const c of credits.value?.crew ?? []) {
    const name = c.department || 'Crew'
    groups.set(name, [...(groups.get(name) ?? []), c])
  }
  return [...groups].map(([name, people]) => ({ name, people }))
})

const open = (c) => props.host.open({ type: 'person', id: c.personID, name: c.name })
const rowClass = 'cursor-pointer w-full flex items-center gap-3 px-4 py-2 text-left hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors'
const card = 'rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 overflow-hidden divide-y divide-black/[0.06] dark:divide-white/8'
</script>

<template>
  <div class="flex flex-col gap-5">
    <h1 class="text-2xl font-bold tracking-tight">{{ parts.title || 'Cast & crew' }}</h1>

    <p v-if="!credits" class="text-center py-16 text-slate-400 dark:text-slate-500">Loading…</p>
    <template v-else>
      <div class="flex rounded-full bg-black/5 dark:bg-white/8 p-0.5" role="group">
        <button
          v-for="t in ['cast', 'crew']"
          :key="t"
          type="button"
          :aria-pressed="tab === t"
          :class="['cursor-pointer flex-1 text-sm font-medium px-3 py-1.5 rounded-full capitalize transition-colors', tab === t ? 'bg-white dark:bg-white/15 shadow-sm' : 'text-slate-500 dark:text-slate-400']"
          @click="tab = t"
        >{{ t }}</button>
      </div>

      <div v-if="tab === 'cast'" :class="card">
        <button v-for="c in credits.cast" :key="`${c.personID}-${c.role}`" type="button" :class="rowClass" @click="open(c)">
          <span class="block w-11 h-11 shrink-0"><PersonPhoto :url="c.photoURL" :name="c.name" /></span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-base text-slate-900 dark:text-white">{{ c.name }}</span>
            <span v-if="c.role" class="block truncate text-[13px] text-slate-500 dark:text-slate-400">{{ c.role }}</span>
          </span>
        </button>
      </div>
      <section v-for="d in tab === 'crew' ? departments : []" :key="d.name" class="flex flex-col gap-2">
        <h2 class="px-1 text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">{{ d.name }}</h2>
        <div :class="card">
          <button v-for="c in d.people" :key="`${c.personID}-${c.role}`" type="button" :class="rowClass" @click="open(c)">
            <span class="block w-11 h-11 shrink-0"><PersonPhoto :url="c.photoURL" :name="c.name" /></span>
            <span class="min-w-0 flex-1">
              <span class="block truncate text-base text-slate-900 dark:text-white">{{ c.name }}</span>
              <span v-if="c.role" class="block truncate text-[13px] text-slate-500 dark:text-slate-400">{{ c.role }}</span>
            </span>
          </button>
        </div>
      </section>
    </template>
  </div>
</template>
