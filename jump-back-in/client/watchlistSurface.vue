<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue'

const props = defineProps({
  items: { type: Array, default: () => [] },
  host: { type: Object, required: true },
  placement: { type: String, default: 'tab' },
})

const LIMIT = 3
const isPanel = computed(() => props.placement === 'panel')

// Unfinished titles with a page to go back to, most recently watched first.
const titles = computed(() => {
  const list = props.host.titles
    .filter((t) => !t.isCompleted && t.resumeHost && t.lastWatchedAt)
    .sort((a, b) => b.lastWatchedAt - a.lastWatchedAt)
  return isPanel.value ? list.slice(0, LIMIT) : list
})

const menu = ref(null)
const closeMenu = () => (menu.value = null)
onMounted(() => window.addEventListener('click', closeMenu))
onBeforeUnmount(() => window.removeEventListener('click', closeMenu))

const clock = (seconds) => {
  const s = Math.max(0, Math.floor(seconds))
  const mm = String(Math.floor((s % 3600) / 60)).padStart(s >= 3600 ? 2 : 1, '0')
  const ss = String(s % 60).padStart(2, '0')
  return s >= 3600 ? `${Math.floor(s / 3600)}:${mm}:${ss}` : `${mm}:${ss}`
}

function subtitle(t) {
  const parts = []
  if (t.kind === 'show' && t.nextEpisode) parts.push(`S${t.nextEpisode.season} E${t.nextEpisode.episode}`)
  parts.push(t.resume ? `${clock(t.resume.position)} / ${clock(t.resume.duration)}` : t.resumeHost)
  return parts.join(' · ')
}

function run(t, action) {
  menu.value = null
  if (action.isDestructive && !window.confirm(`${action.title}\nThis can't be undone.`)) return
  props.host.perform(t.id, action.id)
}
</script>

<template>
  <section v-if="titles.length || !isPanel" class="glass rounded-2xl p-4 flex flex-col gap-3">
    <h2 class="text-sm font-semibold text-slate-500 dark:text-slate-400">Jump back in</h2>

    <p v-if="!titles.length" class="text-sm text-slate-400 dark:text-slate-500">
      Nothing to jump back into yet. Open a title from your list and it will show up here.
    </p>

    <div v-else class="grid gap-3" :class="isPanel ? 'sm:grid-cols-3' : 'sm:grid-cols-2'">
      <div v-for="t in titles" :key="t.id" class="relative group">
        <button
          type="button"
          :aria-label="`Continue watching ${t.title}`"
          class="cursor-pointer w-full flex items-center gap-3 text-left rounded-2xl bg-black/[0.04] dark:bg-white/5 hover:bg-black/[0.07] dark:hover:bg-white/10 transition-colors px-3 py-2.5 pr-9"
          @click="host.resume(t.id)"
        >
          <img v-if="t.posterURL" :src="t.posterURL" alt="" class="w-[52px] h-[78px] rounded-lg object-cover shrink-0" />
          <div v-else class="w-[52px] h-[78px] rounded-lg bg-black/10 dark:bg-white/10 shrink-0" />
          <div class="min-w-0 flex-1 flex flex-col gap-1.5">
            <span class="text-base font-semibold text-slate-900 dark:text-white line-clamp-2">{{ t.title }}</span>
            <span class="text-xs tabular-nums text-slate-500 dark:text-slate-400 truncate">{{ subtitle(t) }}</span>
            <div v-if="t.resume" class="h-1 rounded-full bg-black/10 dark:bg-white/10 overflow-hidden">
              <div class="h-full bg-blue-600" :style="{ width: `${t.resume.fraction * 100}%` }" />
            </div>
          </div>
          <span class="shrink-0 w-9 h-9 rounded-full bg-indigo-600 text-white flex items-center justify-center">
            <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
          </span>
        </button>

        <template v-if="host.resetActions(t.id).length">
          <button
            type="button"
            aria-label="Reset progress"
            class="cursor-pointer absolute top-1 right-1 w-7 h-7 rounded-lg text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            @click.stop="menu = menu === t.id ? null : t.id"
          >
            <svg class="w-4 h-4 mx-auto" viewBox="0 0 24 24" fill="currentColor">
              <circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" />
            </svg>
          </button>
          <div
            v-if="menu === t.id"
            class="absolute right-1 top-9 z-10 min-w-44 rounded-xl bg-white dark:bg-slate-800 shadow-lg p-1 flex flex-col"
            @click.stop
          >
            <button
              v-for="a in host.resetActions(t.id)"
              :key="a.id"
              type="button"
              class="cursor-pointer text-left text-sm px-3 py-1.5 rounded-lg hover:bg-black/5 dark:hover:bg-white/10"
              :class="a.isDestructive ? 'text-red-600 dark:text-red-400' : 'text-slate-700 dark:text-slate-200'"
              @click="run(t, a)"
            >
              {{ a.title }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </section>
</template>
