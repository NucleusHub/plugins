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
  <section v-if="found.length" class="flex flex-col mb-7">
    <h2 class="wl-heading">In the news</h2>
    <div v-glass class="wl-group">
      <ArticleRow v-for="a in found" :key="a.link" :article="a" @open="(x) => host.open({ type: 'web', url: x.link })" />
    </div>
  </section>
</template>
