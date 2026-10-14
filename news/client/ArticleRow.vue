<script setup>
import { ago } from './news.js'

defineProps({ article: { type: Object, required: true } })
defineEmits(['open'])
</script>

<template>
  <button type="button" class="cursor-pointer w-full flex items-start gap-3 px-4 py-3 text-left hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors" @click="$emit('open', article)">
    <div class="min-w-0 flex-1 flex flex-col gap-1">
      <span class="text-[15px] font-semibold leading-snug line-clamp-3">{{ article.title }}</span>
      <span class="text-xs text-slate-500 dark:text-slate-400">{{ article.source }}<template v-if="article.published"> · {{ ago(article.published) }}</template></span>
      <span v-if="article.why" class="text-xs font-medium text-indigo-600 dark:text-indigo-400 line-clamp-2">{{ article.why }}</span>
    </div>
    <img v-if="article.image" :src="article.image" alt="" loading="lazy" referrerpolicy="no-referrer" class="shrink-0 w-16 h-16 rounded-lg object-cover bg-black/5 dark:bg-white/8" />
  </button>
</template>
