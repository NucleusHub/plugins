<script setup>
import { ref, computed, watch } from 'vue'
import PersonPhoto from './PersonPhoto.vue'
import { filmography } from './filmography.js'
import { wikipediaArticle } from './wikipedia.js'

const props = defineProps({
  personId: { type: Number, required: true },
  host: { type: Object, required: true },
})

const GROUP_LIMIT = 12

const person = ref(null)
const failed = ref(false)
const wikipedia = ref(null)
const bioExpanded = ref(false)
const expanded = ref(new Set())

const film = computed(() => (person.value ? filmography(person.value) : null))
const following = computed(() => !!person.value && props.host.isFollowing(person.value.id))

watch(() => props.personId, async (id) => {
  person.value = null
  failed.value = false
  wikipedia.value = null
  expanded.value = new Set()
  try {
    const loaded = await props.host.person(id)
    if (id !== props.personId) return
    person.value = loaded
    if (loaded.wikidataID) wikipediaArticle(loaded.wikidataID).then((url) => { if (id === props.personId) wikipedia.value = url })
  } catch {
    failed.value = true
  }
}, { immediate: true })

const date = (s) => {
  const d = s && new Date(`${s}T00:00:00`)
  return d && !Number.isNaN(d.getTime()) ? d.toLocaleDateString(undefined, { dateStyle: 'long' }) : null
}

// "Born 18 December 1963 · Shawnee, Oklahoma" or "1930 – 2020".
const lifeLine = computed(() => {
  const p = person.value
  const born = date(p?.birthday)
  const died = date(p?.deathday)
  const parts = []
  if (born && died) parts.push(`${born} – ${died}`)
  else if (born) parts.push(`Born ${born}`)
  if (p?.birthplace) parts.push(p.birthplace)
  return parts.join(' · ')
})

const toggleFollow = () => props.host.setFollowing(!following.value, person.value.id, person.value.name, person.value.photoURL)
const toggleGroup = (id) => {
  const next = new Set(expanded.value)
  if (!next.delete(id)) next.add(id)
  expanded.value = next
}
const openTitle = (e) => props.host.open({ type: 'title', kind: e.kind, tmdbID: e.titleID, title: e.title })

const card = 'rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 overflow-hidden'
const heading = 'px-1 text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35'
const pill = 'cursor-pointer nuc-press flex-1 h-12 inline-flex items-center justify-center gap-2 rounded-full text-sm font-semibold transition-colors no-underline'
</script>

<template>
  <p v-if="failed" class="text-center py-16 text-sm text-slate-500 dark:text-slate-400">
    Couldn't load this person. Check your connection and TMDb key.
  </p>
  <p v-else-if="!person" class="text-center py-16 text-slate-400 dark:text-slate-500">Loading…</p>

  <div v-else class="flex flex-col gap-6">
    <header class="flex flex-col items-center gap-3 text-center">
      <span class="block w-36 h-36 shadow-2xl shadow-black/30 rounded-full"><PersonPhoto :url="person.photoURL" :name="person.name" /></span>
      <h1 class="text-2xl font-bold tracking-tight">{{ person.name }}</h1>
      <p v-if="film.occupations.length" class="text-sm font-medium text-indigo-600 dark:text-indigo-400">{{ film.occupations.join(' · ') }}</p>
      <p v-if="lifeLine" class="text-sm text-slate-500 dark:text-slate-400">{{ lifeLine }}</p>
    </header>

    <div class="flex gap-2.5">
      <button
        type="button"
        title="Following someone shapes your MovieDNA."
        :class="[pill, following ? 'bg-black/5 dark:bg-white/10 text-slate-900 dark:text-white' : 'bg-indigo-600 hover:bg-indigo-500 text-white']"
        @click="toggleFollow"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" :d="following ? 'm4.5 12.75 6 6 9-13.5' : 'M12 5v14M5 12h14'" /></svg>
        {{ following ? 'Following' : 'Follow' }}
      </button>
      <a v-if="wikipedia" :href="wikipedia" target="_blank" rel="noopener noreferrer" :class="[pill, 'bg-black/5 dark:bg-white/10 text-slate-900 dark:text-white hover:bg-black/10 dark:hover:bg-white/15']">
        Wikipedia
      </a>
    </div>

    <section v-if="person.biography" class="flex flex-col gap-2">
      <h2 :class="heading">Biography</h2>
      <div :class="[card, 'p-4 flex flex-col gap-2']">
        <p :class="['text-sm leading-relaxed whitespace-pre-line text-slate-700 dark:text-slate-200', bioExpanded ? '' : 'line-clamp-6']">{{ person.biography }}</p>
        <button v-if="person.biography.length > 380" type="button" class="cursor-pointer self-start text-sm font-semibold text-indigo-600 dark:text-indigo-400" @click="bioExpanded = !bioExpanded">
          {{ bioExpanded ? 'Show less' : 'Read more' }}
        </button>
      </div>
    </section>

    <section v-if="film.knownFor.length" class="flex flex-col gap-2">
      <h2 :class="heading">Known for</h2>
      <div :class="[card, 'flex gap-3 overflow-x-auto p-3.5']">
        <button v-for="e in film.knownFor" :key="e.key" type="button" class="cursor-pointer nuc-press w-[110px] shrink-0 flex flex-col gap-1.5 text-left" @click="openTitle(e)">
          <span class="relative block w-[110px] h-[165px] rounded-xl overflow-hidden bg-slate-200 dark:bg-slate-700">
            <img v-if="e.posterURL" :src="e.posterURL" :alt="e.title" loading="lazy" class="w-full h-full object-cover" />
            <span v-if="host.inLibrary(e.kind, e.titleID)" class="absolute top-1.5 right-1.5 grid place-items-center w-5 h-5 rounded-full bg-emerald-600 text-white" title="In your watchlist">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7" /></svg>
            </span>
          </span>
          <span class="text-[13px] font-semibold leading-tight text-slate-900 dark:text-white line-clamp-2">{{ e.title }}</span>
          <span v-if="e.year" class="text-xs text-slate-500 dark:text-slate-400">{{ e.year }}</span>
        </button>
      </div>
    </section>

    <component :is="host.personSections" :person-id="person.id" :name="person.name" />

    <section v-for="g in film.groups" :key="g.id" class="flex flex-col gap-2">
      <h2 :class="heading">{{ g.id }}</h2>
      <div :class="[card, 'divide-y divide-black/[0.06] dark:divide-white/8']">
        <button
          v-for="e in expanded.has(g.id) ? g.entries : g.entries.slice(0, GROUP_LIMIT)"
          :key="e.key"
          type="button"
          class="cursor-pointer w-full flex items-center gap-3 px-4 py-2 text-left hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors"
          @click="openTitle(e)"
        >
          <span class="block w-10 h-[60px] shrink-0 rounded-md overflow-hidden bg-slate-200 dark:bg-slate-700">
            <img v-if="e.posterURL" :src="e.posterURL" :alt="e.title" loading="lazy" class="w-full h-full object-cover" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-base text-slate-900 dark:text-white">{{ e.title }}</span>
            <span class="block truncate text-[13px] text-slate-500 dark:text-slate-400">{{ [e.year, e.roles.join(', ')].filter(Boolean).join(' · ') }}</span>
          </span>
          <span v-if="host.inLibrary(e.kind, e.titleID)" class="shrink-0 grid place-items-center w-5 h-5 rounded-full bg-emerald-600 text-white" title="In your watchlist">
            <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7" /></svg>
          </span>
        </button>
        <button
          v-if="g.entries.length > GROUP_LIMIT"
          type="button"
          class="cursor-pointer w-full px-4 py-3 text-left text-sm text-slate-900 dark:text-white hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors"
          @click="toggleGroup(g.id)"
        >
          {{ expanded.has(g.id) ? 'Show fewer' : `Show all ${g.entries.length}` }}
        </button>
      </div>
    </section>
  </div>
</template>
