<script setup>
import { ref, computed, onMounted } from 'vue'
import ArticleRow from './ArticleRow.vue'
import { interests, forYou } from './news.js'

const props = defineProps({
  page: { type: String, default: 'news' },
  arg: { type: String, default: '' },
  host: { type: Object, required: true },
  // Shown as one of Home's tabs, where the pill already names it.
  asTab: { type: Boolean, default: false },
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
</script>

<template>
  <div class="flex flex-col gap-5">
    <h1 v-if="!asTab" class="px-1 text-[34px] leading-tight font-bold tracking-[-0.02em]">News</h1>

    <div class="flex items-center gap-2">
      <div class="wl-seg wl-seg-static flex flex-1" role="tablist">
        <button
          v-for="t in [['forYou', 'For you'], ['everything', 'Everything']]"
          :key="t[0]"
          type="button"
          role="tab"
          :aria-selected="tab === t[0] ? 'true' : 'false'"
          class="wl-seg-item flex-1 text-center"
          @click="tab = t[0]"
        >{{ t[1] }}</button>
      </div>
      <button
        v-glass.dome
        type="button"
        title="Refresh"
        :disabled="loading"
        class="nuc-press cursor-pointer shrink-0 w-10 h-10 rounded-full grid place-items-center text-[var(--wl-glyph)] hover:text-[var(--wl-text)] disabled:opacity-50 disabled:cursor-default"
        @click="load(true)"
      >
        <svg class="w-[18px] h-[18px]" :class="loading ? 'animate-spin' : ''" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992V4.356M2.985 19.644v-4.992h4.992M19.5 9.5A8 8 0 0 0 5.007 7.5M4.5 14.5A8 8 0 0 0 19 16.5" />
        </svg>
      </button>
    </div>

    <p v-if="!news" class="text-center py-16 text-[var(--wl-text-2)]">Loading…</p>
    <div v-else-if="!articles.length" class="text-center py-16">
      <p class="text-lg font-semibold">Couldn't load the news</p>
      <p class="text-sm text-[var(--wl-text-2)]">Check your connection and refresh to try again.</p>
    </div>
    <div v-else-if="!shown.length" class="text-center py-16">
      <p class="text-lg font-semibold">Nothing about your titles today</p>
      <p class="text-sm text-[var(--wl-text-2)]">Articles that mention your watchlist or people you follow show up here.</p>
    </div>
    <div v-else v-glass class="wl-group">
      <ArticleRow v-for="a in shown" :key="a.link" :article="a" @open="open" />
    </div>

    <p v-if="news?.failed.length && articles.length" class="wl-foot !pt-0">Couldn't reach {{ news.failed.join(', ') }}.</p>
  </div>
</template>
