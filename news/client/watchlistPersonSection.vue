<script setup>
import { ref, computed, onMounted } from 'vue'
import ArticleRow from './ArticleRow.vue'
import { mentions } from './news.js'

const props = defineProps({
  personID: { type: Number, default: 0 },
  name: { type: String, default: '' },
  host: { type: Object, required: true },
})

const articles = ref([])
onMounted(async () => { articles.value = (await props.host.news().catch(() => null))?.articles ?? [] })
const found = computed(() => mentions(articles.value, props.name).slice(0, 5))
</script>

<template>
  <section v-if="found.length" class="flex flex-col gap-2">
    <h2 class="px-1 text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-white/35">In the news</h2>
    <div class="rounded-xl bg-white/60 dark:bg-slate-800/50 border border-white/60 dark:border-white/8 overflow-hidden divide-y divide-black/[0.06] dark:divide-white/8">
      <ArticleRow v-for="a in found" :key="a.link" :article="a" @open="(x) => host.open({ type: 'web', url: x.link })" />
    </div>
  </section>
</template>
