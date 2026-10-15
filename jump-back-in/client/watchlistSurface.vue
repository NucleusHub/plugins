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
  <section v-if="titles.length || !isPanel" class="flex flex-col">
    <h2 class="wl-heading">Jump back in</h2>

    <p v-if="!titles.length" class="px-4 text-sm text-[var(--wl-text-2)]">
      Nothing to jump back into yet. Open a title from your list and it will show up here.
    </p>

    <div v-else class="grid gap-3" :class="isPanel ? 'sm:grid-cols-3' : 'sm:grid-cols-2'">
      <div v-for="t in titles" :key="t.id" class="relative group">
        <button
          type="button"
          :aria-label="`Continue watching ${t.title}`"
          class="wl-row wl-surface rounded-[20px] !py-2.5 !pl-3 !pr-9"
          @click="host.resume(t.id)"
        >
          <img v-if="t.posterURL" :src="t.posterURL" alt="" v-squircle class="w-[52px] h-[78px] rounded-[8px] object-cover shrink-0" />
          <div v-else class="w-[52px] h-[78px] rounded-[8px] bg-[var(--wl-well)] shrink-0" />
          <div class="min-w-0 flex-1 flex flex-col gap-1.5">
            <span class="text-base font-semibold text-[var(--wl-text)] line-clamp-2">{{ t.title }}</span>
            <span class="text-xs tabular-nums text-[var(--wl-text-2)] truncate">{{ subtitle(t) }}</span>
            <div v-if="t.resume" class="h-1 rounded-full bg-[var(--wl-well)] overflow-hidden">
              <div class="h-full bg-[#2A78D6]" :style="{ width: `${t.resume.fraction * 100}%` }" />
            </div>
          </div>
          <span class="shrink-0 w-9 h-9 rounded-full bg-gradient-to-br from-indigo-500 to-violet-500 text-white flex items-center justify-center">
            <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>
          </span>
        </button>

        <template v-if="host.resetActions(t.id).length">
          <button
            type="button"
            aria-label="Reset progress"
            class="cursor-pointer absolute top-2 right-2 w-7 h-7 rounded-full text-[var(--wl-text-2)] hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
            @click.stop="menu = menu === t.id ? null : t.id"
          >
            <svg class="w-4 h-4 mx-auto" viewBox="0 0 24 24" fill="currentColor">
              <circle cx="5" cy="12" r="1.8" /><circle cx="12" cy="12" r="1.8" /><circle cx="19" cy="12" r="1.8" />
            </svg>
          </button>
          <div
            v-if="menu === t.id"
            v-glass class="absolute right-1 top-9 z-10 min-w-44 rounded-[16px] p-1 flex flex-col"
            @click.stop
          >
            <button
              v-for="a in host.resetActions(t.id)"
              :key="a.id"
              type="button"
              class="cursor-pointer text-left text-sm px-3 py-1.5 rounded-lg hover:bg-black/5 dark:hover:bg-white/10"
              :class="a.isDestructive ? 'text-red-600 dark:text-red-400' : 'text-[var(--wl-text)]'"
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
