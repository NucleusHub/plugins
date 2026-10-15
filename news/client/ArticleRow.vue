<script setup>
import { ago } from './news.js'

defineProps({ article: { type: Object, required: true } })
defineEmits(['open'])
</script>

<template>
  <button type="button" class="wl-row !items-start !py-3.5" @click="$emit('open', article)">
    <div class="min-w-0 flex-1 flex flex-col gap-1">
      <span class="text-[15px] font-semibold leading-snug line-clamp-3">{{ article.title }}</span>
      <span class="text-xs text-[var(--wl-text-2)]">{{ article.source }}<template v-if="article.published"> · {{ ago(article.published) }}</template></span>
      <span v-if="article.why" class="text-xs font-medium text-[var(--wl-accent)] line-clamp-2">{{ article.why }}</span>
    </div>
    <img v-if="article.image" v-squircle :src="article.image" alt="" loading="lazy" referrerpolicy="no-referrer" class="shrink-0 w-16 h-16 rounded-[12px] object-cover bg-[var(--wl-well)]" />
  </button>
</template>
