<script setup>
import { ref, computed, watch } from 'vue'
import { signals, genreAffinity, topGenres, rankBacklog } from './taste.js'
import { discover, clearDiscoverCache } from './discover.js'
import { NoKeyError, posterUrl } from './tmdb.js'
import { addToWatchlist } from './api.js'
import { useHost } from './host.js'
import { Icon } from '@core/icons'
import RecCard from './RecCard.vue'

const props = defineProps({
  items: { type: Array, default: () => [] },
  placement: { type: String, default: 'tab' },
})
const emit = defineEmits(['changed'])

const isPanel = computed(() => props.placement === 'panel')
const limit = computed(() => (isPanel.value ? 6 : 12))

const type = ref('all')
const TYPES = [
  { key: 'all', label: 'All' },
  { key: 'movie', label: 'Movies' },
  { key: 'show', label: 'Shows' },
]

const signalList = computed(() => signals(props.items))
const affinity = computed(() => genreAffinity(signalList.value))
const lead = computed(() => topGenres(affinity.value, 4))
const recentTitles = computed(() =>
  signalList.value.filter((s) => s.weight > 0).slice(0, 3).map((s) => s.item.title)
)

const backlog = computed(() =>
  rankBacklog(props.items, {
    affinity: affinity.value,
    signals: signalList.value,
    type: type.value,
    limit: limit.value,
  })
)

const hasWatched = computed(() => signalList.value.length > 0)
const hasGenres = computed(() => affinity.value.size > 0)

const discovered = ref([])
const discovering = ref(false)
const discoverError = ref(null)
const offset = ref(0)
const poolSize = ref(0)

async function loadDiscover(force = false) {
  if (!hasWatched.value) {
    discovered.value = []
    poolSize.value = 0
    return
  }
  discovering.value = true
  discoverError.value = null
  try {
    if (force) clearDiscoverCache()
    const res = await discover(props.items, {
      affinity: affinity.value,
      signals: signalList.value,
      type: type.value,
      limit: limit.value,
      offset: offset.value,
      force,
    })
    discovered.value = res.results
    poolSize.value = res.poolSize
  } catch (err) {
    discovered.value = []
    poolSize.value = 0
    discoverError.value = err instanceof NoKeyError ? 'no-key' : 'failed'
  } finally {
    discovering.value = false
  }
}

function showDifferent() {
  offset.value += limit.value
  loadDiscover(false)
}

const canRotate = computed(() => poolSize.value > limit.value)

const refreshAction = computed(() => {
  if (discoverError.value === 'no-key') return null
  if (discoverError.value) return 'retry'
  return canRotate.value ? 'rotate' : null
})

const REFRESH_TITLE = {
  retry: 'Try TMDb again',
  rotate: 'Show different suggestions',
}

function onRefresh() {
  if (refreshAction.value === 'retry') {
    offset.value = 0
    loadDiscover(true)
  } else if (refreshAction.value === 'rotate') {
    showDifferent()
  }
}

const poolKey = computed(() =>
  [
    type.value,
    signalList.value.filter((s) => s.item.tmdbId && s.weight > 0).slice(0, 4).map((s) => s.item.tmdbId).join(','),
  ].join('|')
)

const discoverKey = computed(() => `${poolKey.value}|${props.items.length}`)

// Must be registered before the discoverKey watcher so the offset resets first.
watch(poolKey, () => { offset.value = 0 })
watch(discoverKey, () => loadDiscover(false), { immediate: true })

const adding = ref(new Set())
const addFailed = ref(new Set())

async function add(candidate) {
  if (adding.value.has(candidate.key)) return
  adding.value = new Set(adding.value).add(candidate.key)
  addFailed.value = new Set([...addFailed.value].filter((k) => k !== candidate.key))
  try {
    await addToWatchlist(candidate)
    discovered.value = discovered.value.filter((c) => c.key !== candidate.key)
    emit('changed')
  } catch {
    addFailed.value = new Set(addFailed.value).add(candidate.key)
  } finally {
    const next = new Set(adding.value)
    next.delete(candidate.key)
    adding.value = next
  }
}

const starting = ref(new Set())

async function start(item) {
  if (starting.value.has(item._id)) return
  starting.value = new Set(starting.value).add(item._id)
  try {
    await useHost().updateItem(item._id, { status: 'watching' })
    emit('changed')
  } catch {
  } finally {
    const next = new Set(starting.value)
    next.delete(item._id)
    starting.value = next
  }
}

const cardWrapClass = computed(() =>
  isPanel.value
    ? 'flex gap-3 overflow-x-auto no-scrollbar pb-1 -mx-1 px-1'
    : 'grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4'
)
</script>

<template>
  <section class="glass rounded-2xl p-4 flex flex-col gap-4">
    <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
      <div class="min-w-0">
        <h2 class="text-base font-semibold text-slate-900 dark:text-white">For You</h2>
        <p v-if="lead.length" class="mt-0.5 text-xs text-slate-400 dark:text-slate-500">
          Lately you've been into
          <span class="text-slate-500 dark:text-slate-400 font-medium">{{ lead.map((g) => g.name).join(' · ') }}</span>
        </p>
        <p v-else-if="hasWatched" class="mt-0.5 text-xs text-slate-400 dark:text-slate-500">
          Your finished titles have no genres yet — hit Refresh on the watchlist to fill them in.
        </p>
        <p v-else class="mt-0.5 text-xs text-slate-400 dark:text-slate-500">
          Mark something completed and this starts working.
        </p>
      </div>

      <div class="inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1 shrink-0 self-start sm:self-auto">
        <button
          v-for="tab in TYPES"
          :key="tab.key"
          @click="type = tab.key"
          :class="[
            'cursor-pointer whitespace-nowrap px-2.5 py-1 rounded-lg text-xs font-medium transition-all',
            type === tab.key
              ? 'bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm'
              : 'text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white',
          ]"
        >
          {{ tab.label }}
        </button>
      </div>
    </div>

    <p v-if="!hasWatched" class="text-sm text-slate-500 dark:text-slate-400">
      Once you've finished a few things, this reads their genres — weighted by how recently you
      watched them and how you rated them — and uses that to rank your backlog and find new titles.
    </p>

    <template v-else>
      <div class="flex flex-col gap-2">
        <div class="flex items-baseline justify-between gap-3">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">Up next from your list</h3>
          <span v-if="recentTitles.length" class="hidden sm:block text-xs text-slate-400 dark:text-slate-500 truncate">
            because you watched {{ recentTitles.join(', ') }}
          </span>
        </div>

        <p v-if="!backlog.results.length" class="text-sm text-slate-400 dark:text-slate-500">
          Nothing planned{{ type === 'all' ? '' : ` in ${type === 'movie' ? 'movies' : 'shows'}` }} — add something and it'll be ranked here.
        </p>
        <p v-else-if="!hasGenres" class="text-xs text-amber-600 dark:text-amber-400">
          Ordered by rating only for now: none of your finished titles carry genres yet.
        </p>

        <div v-if="backlog.results.length" :class="cardWrapClass">
          <RecCard
            v-for="r in backlog.results"
            :key="r.item._id"
            :title="r.item.title"
            :year="r.item.year"
            :poster="r.item.posterUrl"
            :rating="r.item.rating ?? r.item.tmdbRating"
            :genres="r.item.genres"
            :why="r.why"
            :compact="isPanel"
            action-label="Start watching"
            :busy="starting.has(r.item._id)"
            @action="start(r.item)"
          />
        </div>
      </div>

      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between gap-3">
          <h3 class="text-sm font-semibold text-slate-700 dark:text-slate-200">New to you</h3>
          <div class="flex items-center gap-1.5 shrink-0">
            <span class="text-xs text-slate-400 dark:text-slate-500">from TMDb</span>
            <button
              @click="onRefresh"
              :disabled="discovering || !refreshAction"
              :title="REFRESH_TITLE[refreshAction] ?? 'Nothing more to suggest right now'"
              class="nuc-press cursor-pointer h-7 px-1.5 rounded-lg text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <Icon name="refresh" class="w-3.5 h-3.5" :class="discovering ? 'animate-spin' : ''" />
            </button>
          </div>
        </div>

        <p v-if="discoverError === 'no-key'" class="text-xs text-slate-400 dark:text-slate-500">
          TMDb isn't configured for this install, so there's nothing to discover from. The ranking
          of your own list above works without it.
        </p>
        <p v-else-if="discoverError" class="text-xs text-amber-600 dark:text-amber-400">
          Couldn't reach TMDb. Use the retry button above.
        </p>
        <p v-else-if="discovering && !discovered.length" class="text-sm text-slate-400 dark:text-slate-500">
          Looking for something new…
        </p>
        <p v-else-if="!discovered.length" class="text-sm text-slate-400 dark:text-slate-500">
          Nothing new to suggest right now — everything close to your recent watching is already on
          your list.
        </p>

        <div v-if="discovered.length" :class="cardWrapClass">
          <RecCard
            v-for="c in discovered"
            :key="c.key"
            :title="c.title"
            :year="c.year"
            :poster="posterUrl(c.posterPath, 'w342')"
            :rating="c.tmdbRating"
            :genres="c.genres"
            :why="c.why"
            :compact="isPanel"
            :action-label="addFailed.has(c.key) ? 'Retry' : 'Add to list'"
            :busy="adding.has(c.key)"
            :danger="addFailed.has(c.key)"
            @action="add(c)"
          />
        </div>
      </div>
    </template>
  </section>
</template>
