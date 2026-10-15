<script setup>
import { ref, computed, watch } from 'vue'
import PersonPhoto from './PersonPhoto.vue'

const props = defineProps({
  kind: { type: String, required: true },
  tmdbID: { type: Number, default: null },
  title: { type: String, default: '' },
  host: { type: Object, required: true },
  canNavigate: { type: Boolean, default: true },
  // Entered by hand for titles TMDb doesn't have; shown as they are.
  credits: { type: Object, default: null },
})

// The jobs that say who made it; the rest of the crew waits for "See all".
const KEY_JOBS = new Set(['Director', 'Creator', 'Screenplay', 'Writer', 'Novel', 'Original Music Composer', 'Composer'])

const fetched = ref(null)
watch(() => [props.kind, props.tmdbID], async () => {
  fetched.value = null
  if (props.credits || !props.tmdbID) return
  fetched.value = await props.host.credits(props.kind, props.tmdbID).catch(() => null)
}, { immediate: true })

// Key crew, one bubble per person with their jobs joined, then the top-billed cast.
// Hand-entered credits are short and chosen on purpose, so all their crew shows.
const people = computed(() => {
  const all = props.credits ?? fetched.value
  if (!all) return []
  const given = !!props.credits
  const crew = []
  for (const c of all.crew) {
    if (!given && !KEY_JOBS.has(c.role)) continue
    const prev = crew.find((p) => p.personID === c.personID && (c.personID > 0 || p.name === c.name))
    if (prev) prev.role = `${prev.role}, ${c.role}`
    else crew.push({ ...c })
  }
  return [...crew.slice(0, given ? 20 : 4), ...all.cast.slice(0, 20)]
})

// Someone typed in by hand has no TMDb page to open.
const canOpen = (p) => props.canNavigate && p.personID > 0
const openPerson = (p) => props.host.open({ type: 'person', id: p.personID, name: p.name })
const seeAll = () => props.host.open({ type: 'page', plugin: 'cast-and-crew', page: 'credits', arg: `${props.kind}:${props.tmdbID}:${props.title}` })
</script>

<template>
  <section v-if="people.length" class="flex flex-col mb-7">
    <h2 class="wl-heading">Cast &amp; crew</h2>
    <div v-glass class="wl-group">
      <div class="flex gap-3.5 overflow-x-auto no-scrollbar p-4">
        <component
          :is="canOpen(p) ? 'button' : 'div'"
          v-for="p in people"
          :key="`${p.personID}-${p.department}-${p.role}-${p.name}`"
          :type="canOpen(p) ? 'button' : undefined"
          :class="['w-[90px] shrink-0 flex flex-col items-center gap-1.5 text-center', canOpen(p) ? 'cursor-pointer nuc-press' : '']"
          @click="canOpen(p) && openPerson(p)"
        >
          <span class="block w-[76px] h-[76px]"><PersonPhoto :url="p.photoURL" :name="p.name" /></span>
          <span class="text-[13px] font-semibold leading-tight line-clamp-2">{{ p.name }}</span>
          <span v-if="p.role" class="text-xs leading-tight text-[var(--wl-text-2)] line-clamp-2">{{ p.role }}</span>
        </component>
      </div>
      <button
        v-if="canNavigate && !credits && tmdbID"
        type="button"
        class="wl-row"
        @click="seeAll"
      >
        <span class="flex-1">See all cast &amp; crew</span>
        <svg class="w-3.5 h-3.5 text-slate-400" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" /></svg>
      </button>
    </div>
  </section>
</template>
