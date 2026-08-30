<script setup>
import { ref, computed, watch } from 'vue'
import { signals, genreAffinity, topGenres, rankBacklog } from './taste.js'
import { discover, clearDiscoverCache } from './discover.js'
import { NoKeyError, posterUrl } from './tmdb.js'
import { addToWatchlist } from './api.js'
import { Icon } from '@core/icons'
import RecCard from './RecCard.vue'

// The For You surface. Mounted by the host either as its own tab (wrapped in
// views/PluginSurfaceView.vue) or as a panel above the item grid on the main
// watchlist — same component, told which by `placement`, since the only real
// difference is how much room it has.
//
// Two sections, deliberately in this order:
//   "Up next"   your own backlog, re-ranked against your recent viewing. Costs
//               nothing, works offline, and answers the question people
//               actually have most nights — I own 200 things, what now?
//   "New to you" titles you don't have, from TMDb. The discovery half; degrades
//               to an explained gap when there's no API key or the network is
//               down, without taking the first section with it.
const props = defineProps({
  // The viewer's full watchlist, loaded by the host.
  items: { type: Array, default: () => [] },
  placement: { type: String, default: 'tab' },
})
const emit = defineEmits(['changed'])

const isPanel = computed(() => props.placement === 'panel')
// A panel sits above someone's actual list, so it shows one tight row; the tab
// is the destination and can fill the page.
const limit = computed(() => (isPanel.value ? 6 : 12))

const type = ref('all')
const TYPES = [
  { key: 'all', label: 'All' },
  { key: 'movie', label: 'Movies' },
  { key: 'show', label: 'Shows' },
]

// ── The taste profile ────────────────────────────────────────────────────────
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

// Nothing finished yet means there's no profile to build — a different problem
// from "finished things, but none of them are tagged", so they get different
// explanations.
const hasWatched = computed(() => signalList.value.length > 0)
const hasGenres = computed(() => affinity.value.size > 0)

// ── Discovery ────────────────────────────────────────────────────────────────
const discovered = ref([])
const discovering = ref(false)
const discoverError = ref(null)
// How far into the scored pool the visible window starts. The "show different
// ones" button advances this rather than re-querying TMDb: the ranking is
// deterministic, so a fresh round-trip would rebuild the identical list and
// hand back the identical head of it. Paging is instant and actually different.
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

// Next windowful. `discover` wraps the offset around the pool, so pressing past
// the end returns to the top rather than emptying the section.
function showDifferent() {
  offset.value += limit.value
  loadDiscover(false)
}

// Only worth offering when there's more in the pool than fits on screen —
// otherwise the button would just redraw the same cards.
const canRotate = computed(() => poolSize.value > limit.value)

// One button, two jobs. After a failed lookup it's the retry (a real refetch is
// exactly what's wanted then); otherwise it pages the pool. With no key, or
// nothing left to page to, there's no honest job for it and it's disabled.
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

// Which pool we're looking at: the titles that seed it and the type filter.
// When this changes the pool itself is different, so paging starts over.
const poolKey = computed(() =>
  [
    type.value,
    signalList.value.filter((s) => s.item.tmdbId && s.weight > 0).slice(0, 4).map((s) => s.item.tmdbId).join(','),
  ].join('|')
)

// What the visible list depends on: the pool, plus the library size — adding or
// removing an item changes what gets filtered out of the window. Watching the
// items array itself would re-run on every unrelated edit (a note, a rating on
// something old).
const discoverKey = computed(() => `${poolKey.value}|${props.items.length}`)

// Declared first so it runs first: a new pool resets paging, and the reload
// below then reads the reset offset. Adding a suggestion changes discoverKey but
// NOT poolKey, so it re-filters the window in place instead of yanking you back
// to the first page.
watch(poolKey, () => { offset.value = 0 })
watch(discoverKey, () => loadDiscover(false), { immediate: true })

// ── Adding a suggestion ──────────────────────────────────────────────────────
const adding = ref(new Set())
const addFailed = ref(new Set())

async function add(candidate) {
  if (adding.value.has(candidate.key)) return
  adding.value = new Set(adding.value).add(candidate.key)
  addFailed.value = new Set([...addFailed.value].filter((k) => k !== candidate.key))
  try {
    await addToWatchlist(candidate)
    // Drop it locally straight away so the card doesn't linger while the host
    // reloads; the reload then filters it out for good.
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

// ── Starting something from the backlog ──────────────────────────────────────
const starting = ref(new Set())

async function start(item) {
  if (starting.value.has(item._id)) return
  starting.value = new Set(starting.value).add(item._id)
  try {
    const res = await fetch(`/api/watchlist/${item._id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify({ status: 'watching' }),
    })
    if (res.ok) emit('changed')
  } catch {
    // The host reload never happens; the card stays put, which is the honest
    // outcome of a failed write.
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
    <!-- Header: what this is, what it's reading, and the controls -->
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

      <!-- Only the type filter lives up here: it's the one control that changes
           both sections. Anything that acts on a single section sits on that
           section's own heading. -->
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

    <!-- Nothing to work from yet -->
    <p v-if="!hasWatched" class="text-sm text-slate-500 dark:text-slate-400">
      Once you've finished a few things, this reads their genres — weighted by how recently you
      watched them and how you rated them — and uses that to rank your backlog and find new titles.
    </p>

    <template v-else>
      <!-- ── Up next from your list ──────────────────────────────────────── -->
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

      <!-- ── New to you ──────────────────────────────────────────────────── -->
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
              <!-- The host's own refresh glyph, so this reads as the same kind of
                   action as the watchlist header's refresh, not a lookalike. -->
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
