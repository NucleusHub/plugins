<script setup>
import { computed, onMounted, watch } from 'vue'
import SuggestionCard from './SuggestionCard.vue'
import { state, refresh, remove, fingerprint } from './feed.js'

const props = defineProps({
  items: { type: Array, default: () => [] },
  host: { type: Object, required: true },
  placement: { type: String, default: 'tab' },
})

const isPanel = computed(() => props.placement === 'panel')
const feed = computed(() => state.feed)
const empty = computed(() => !(feed.value.picks.length || feed.value.following.length || feed.value.newReleases.length || feed.value.trending.length || feed.value.different.length))

const rows = computed(() => {
  const f = feed.value
  const rest = [
    { key: 'following', title: 'From people you follow', list: f.following },
    { key: 'new', title: 'New releases', subtitle: 'In cinemas and on air now', list: f.newReleases },
    { key: 'trending', title: 'Trending this week', list: f.trending },
    { key: 'different', title: 'Outside your comfort zone', subtitle: 'Highly rated, from genres you haven\'t tried', list: f.different },
  ]
  const picks = { key: 'picks', title: state.usesDNA ? 'Picked for you' : 'For you', subtitle: state.usesDNA ? 'From your MovieDNA' : '', list: f.picks }
  return [picks, ...(isPanel.value ? [] : rest)].filter((r) => r.list.length)
})

const reload = (force = false) => refresh(props.host, force)
onMounted(() => reload())
// Interested presses, strength edits and follows change what's suggested.
watch(() => fingerprint(props.host.movieDNA), () => reload())

const rowClass = 'flex gap-3 overflow-x-auto no-scrollbar pb-1 -mx-1 px-1'
</script>

<template>
  <section class="glass rounded-2xl p-4 flex flex-col gap-5">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="text-base font-semibold text-slate-900 dark:text-white">Discover</h2>
        <p v-if="!state.usesDNA && !empty" class="mt-0.5 text-xs text-slate-400 dark:text-slate-500">
          MovieDNA is off, so these come from what you've watched.
        </p>
      </div>
      <button
        v-if="host.hasTMDbKey"
        type="button"
        title="Refresh"
        :disabled="state.loading"
        class="cursor-pointer shrink-0 h-7 px-1.5 rounded-lg text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        @click="reload(true)"
      >
        <svg class="w-3.5 h-3.5" :class="state.loading ? 'animate-spin' : ''" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992V4.356M2.985 19.644v-4.992h4.992M19.5 9.5A8 8 0 0 0 5 7.5M4.5 14.5A8 8 0 0 0 19 16.5" />
        </svg>
      </button>
    </div>

    <p v-if="!host.hasTMDbKey" class="text-sm text-slate-500 dark:text-slate-400">
      TMDb isn't configured for this install, so there's nothing to discover from.
    </p>
    <p v-else-if="empty && state.failed" class="text-sm text-amber-600 dark:text-amber-400">
      Couldn't load Discover. Check your connection and refresh.
    </p>
    <p v-else-if="empty" class="text-sm text-slate-400 dark:text-slate-500">
      {{ state.loading ? 'Looking for something you\'ll like…' : 'Nothing to suggest yet. Rate a few titles and check back.' }}
    </p>

    <template v-else>
      <div v-for="row in rows" :key="row.key" class="flex flex-col gap-2">
        <div>
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">{{ row.title }}</h3>
          <p v-if="row.subtitle" class="text-xs text-slate-400 dark:text-slate-500">{{ row.subtitle }}</p>
        </div>
        <div :class="rowClass">
          <SuggestionCard v-for="s in row.list" :key="s.id" :suggestion="s" :host="host" @not-interested="remove" />
        </div>
        <!-- Trailers sit right under the picks, as on iOS. -->
        <template v-if="row.key === 'picks' && !isPanel && feed.trailers.length">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200 mt-3">Trailers for you</h3>
          <div :class="rowClass">
            <button
              v-for="t in feed.trailers"
              :key="t.key"
              type="button"
              class="cursor-pointer w-60 shrink-0 flex flex-col gap-1.5 text-left"
              @click="host.playTrailer(t.key)"
            >
              <span class="relative block aspect-video rounded-xl overflow-hidden bg-slate-100 dark:bg-slate-700/60">
                <img :src="`https://img.youtube.com/vi/${t.key}/hqdefault.jpg`" :alt="t.title.title" loading="lazy" class="w-full h-full object-cover" />
                <span class="absolute inset-0 grid place-items-center">
                  <span class="grid place-items-center w-11 h-11 rounded-full bg-black/55 text-white">
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
                  </span>
                </span>
              </span>
              <span class="truncate text-sm font-semibold text-slate-900 dark:text-white">{{ t.title.title }}</span>
            </button>
          </div>
        </template>
      </div>
    </template>
  </section>
</template>
