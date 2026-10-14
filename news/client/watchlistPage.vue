<script setup>
import { ref, computed, onMounted } from 'vue'
import ArticleRow from './ArticleRow.vue'
import { interests, forYou } from './news.js'

const props = defineProps({
  page: { type: String, default: 'news' },
  arg: { type: String, default: '' },
  host: { type: Object, required: true },
})

const tab = ref('forYou')
const news = ref(null)
const loading = ref(false)

async function load(refresh = false) {
  loading.value = true
  try { news.value = await props.host.news(refresh) } catch { news.value ??= { articles: [], failed: [] } } finally { loading.value = false }
}
onMounted(() => load())

const articles = computed(() => news.value?.articles ?? [])
const matched = computed(() => forYou(articles.value, interests(props.host.movieDNA, props.host.library)))
const shown = computed(() => (tab.value === 'forYou' ? matched.value : articles.value))
const open = (a) => props.host.open({ type: 'web', url: a.link })
const card = 'rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 overflow-hidden divide-y divide-black/[0.06] dark:divide-white/8'
</script>

<template>
  <div class="flex flex-col gap-5">
    <div class="flex items-center justify-between gap-3">
      <h1 class="text-2xl font-bold tracking-tight">News</h1>
      <button type="button" title="Refresh" :disabled="loading" class="cursor-pointer h-8 px-2 rounded-lg text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8 transition-colors disabled:opacity-40 disabled:cursor-not-allowed" @click="load(true)">
        <svg class="w-4 h-4" :class="loading ? 'animate-spin' : ''" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992V4.356M2.985 19.644v-4.992h4.992M19.5 9.5A8 8 0 0 0 5.007 7.5M4.5 14.5A8 8 0 0 0 19 16.5" />
        </svg>
      </button>
    </div>

    <div class="flex rounded-full bg-black/5 dark:bg-white/8 p-0.5" role="group">
      <button
        v-for="t in [['forYou', 'For you'], ['everything', 'Everything']]"
        :key="t[0]"
        type="button"
        :aria-pressed="tab === t[0]"
        class="cursor-pointer flex-1 rounded-full py-1.5 text-sm font-semibold transition-colors"
        :class="tab === t[0] ? 'bg-white dark:bg-slate-700 shadow-sm' : 'text-slate-500 dark:text-slate-400'"
        @click="tab = t[0]"
      >{{ t[1] }}</button>
    </div>

    <p v-if="!news" class="text-center py-16 text-slate-400 dark:text-slate-500">Loading…</p>
    <div v-else-if="!articles.length" class="text-center py-16">
      <p class="font-semibold">Couldn't load the news</p>
      <p class="text-sm text-slate-400 dark:text-slate-500">Check your connection and refresh to try again.</p>
    </div>
    <div v-else-if="!shown.length" class="text-center py-16">
      <p class="font-semibold">Nothing about your titles today</p>
      <p class="text-sm text-slate-400 dark:text-slate-500">Articles that mention your watchlist or people you follow show up here.</p>
    </div>
    <div v-else :class="card">
      <ArticleRow v-for="a in shown" :key="a.link" :article="a" @open="open" />
    </div>

    <p v-if="news?.failed.length && articles.length" class="px-1 text-xs text-slate-400 dark:text-slate-500">Couldn't reach {{ news.failed.join(', ') }}.</p>
  </div>
</template>
