<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  suggestion: { type: Object, required: true },
  host: { type: Object, required: true },
})
const emit = defineEmits(['notInterested'])

const adding = ref(false)
const failed = ref(false)
const added = computed(() => props.host.inLibrary(props.suggestion.kind, props.suggestion.tmdbID))
const year = computed(() => props.suggestion.date?.slice(0, 4) ?? '')

const why = computed(() => {
  const r = props.suggestion.reason
  switch (r.type) {
    case 'because': return `Because you liked ${r.title}`
    case 'following': return [r.name, year.value].filter(Boolean).join(' · ')
    case 'genres': return r.names.length ? r.names.join(' · ') : year.value
    case 'different': return `Something new: ${r.genre}`
    default: return year.value
  }
})

function open() {
  const s = props.suggestion
  props.host.open({ type: 'title', kind: s.kind, tmdbID: s.tmdbID, title: s.title, year: year.value })
}

async function add() {
  if (adding.value || added.value) return
  adding.value = true
  failed.value = false
  try {
    await props.host.addToWatchlist(props.suggestion.kind, props.suggestion.tmdbID)
  } catch {
    failed.value = true
  } finally {
    adding.value = false
  }
}

function notInterested() {
  const s = props.suggestion
  props.host.markNotInterested(s.kind, s.tmdbID, s.title, s.genres)
  emit('notInterested', s.id)
}
</script>

<template>
  <article class="w-[132px] shrink-0 flex flex-col gap-2">
    <div v-squircle class="relative aspect-[2/3] rounded-[14px] overflow-hidden bg-[var(--wl-well)] shadow-[0_8px_20px_-8px_rgb(0_0_0/0.45)]">
      <button type="button" class="cursor-pointer block w-full h-full" :title="suggestion.title" @click="open">
        <img :src="suggestion.posterURL" :alt="suggestion.title" loading="lazy" class="w-full h-full object-cover" />
      </button>
      <button
        v-if="!added"
        type="button"
        title="Not interested"
        class="cursor-pointer absolute top-1.5 left-1.5 grid place-items-center w-6 h-6 rounded-full bg-black/35 backdrop-blur-md text-white hover:bg-black/60 transition-colors"
        @click="notInterested"
      >
        <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" d="M6 6l12 12M18 6 6 18" /></svg>
      </button>
      <button
        type="button"
        :disabled="added || adding"
        :title="added ? 'In your watchlist' : 'Add to watchlist'"
        :class="[
          'absolute top-1.5 right-1.5 grid place-items-center w-8 h-8 rounded-full text-white shadow transition-colors',
          added ? 'bg-[#1BAF7A]' : failed ? 'bg-red-600/90 cursor-pointer' : 'bg-gradient-to-br from-indigo-500 to-violet-500 hover:brightness-110 cursor-pointer',
        ]"
        @click="add"
      >
        <span v-if="adding" class="w-3.5 h-3.5 rounded-full border-2 border-white/40 border-t-white animate-spin" />
        <svg v-else-if="added" class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m5 13 4 4L19 7" /></svg>
        <span v-else-if="failed" class="text-sm font-bold leading-none">!</span>
        <svg v-else class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24"><path stroke-linecap="round" d="M12 5v14M5 12h14" /></svg>
      </button>
    </div>
    <h4 class="text-[13px] font-semibold leading-tight text-[var(--wl-text)] line-clamp-2" :title="suggestion.title">{{ suggestion.title }}</h4>
    <p v-if="why" class="text-xs leading-snug text-[var(--wl-text-2)] line-clamp-2">{{ why }}</p>
  </article>
</template>
