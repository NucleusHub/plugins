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
const rowClass = 'wl-row !py-2'
const card = 'wl-group'
</script>

<template>
  <div class="flex flex-col gap-5">
    <h1 class="px-1 text-[34px] leading-tight font-bold tracking-[-0.02em]">{{ parts.title || 'Cast & crew' }}</h1>

    <p v-if="!credits" class="text-center py-16 text-[var(--wl-text-2)]">Loading…</p>
    <template v-else>
      <div class="wl-seg wl-seg-static flex" role="tablist">
        <button
          v-for="t in ['cast', 'crew']"
          :key="t"
          type="button"
          role="tab"
          :aria-selected="tab === t ? 'true' : 'false'"
          class="wl-seg-item flex-1 text-center capitalize"
          @click="tab = t"
        >{{ t }}</button>
      </div>

      <div v-if="tab === 'cast'" v-glass :class="card">
        <button v-for="c in credits.cast" :key="`${c.personID}-${c.role}`" type="button" :class="rowClass" @click="open(c)">
          <span class="block w-11 h-11 shrink-0"><PersonPhoto :url="c.photoURL" :name="c.name" /></span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-base text-[var(--wl-text)]">{{ c.name }}</span>
            <span v-if="c.role" class="block truncate text-[13px] text-[var(--wl-text-2)]">{{ c.role }}</span>
          </span>
        </button>
      </div>
      <section v-for="d in tab === 'crew' ? departments : []" :key="d.name" class="flex flex-col gap-2">
        <h2 class="wl-heading !pb-0">{{ d.name }}</h2>
        <div v-glass :class="card">
          <button v-for="c in d.people" :key="`${c.personID}-${c.role}`" type="button" :class="rowClass" @click="open(c)">
            <span class="block w-11 h-11 shrink-0"><PersonPhoto :url="c.photoURL" :name="c.name" /></span>
            <span class="min-w-0 flex-1">
              <span class="block truncate text-base text-[var(--wl-text)]">{{ c.name }}</span>
              <span v-if="c.role" class="block truncate text-[13px] text-[var(--wl-text-2)]">{{ c.role }}</span>
            </span>
          </button>
        </div>
      </section>
    </template>
  </div>
</template>
