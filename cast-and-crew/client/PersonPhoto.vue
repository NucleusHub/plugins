<script setup>
import { computed } from 'vue'

const props = defineProps({
  url: { type: String, default: null },
  name: { type: String, default: '' },
})
const initials = computed(() => props.name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase())
</script>

<template>
  <img v-if="url" :src="url" :alt="name" loading="lazy" class="w-full h-full rounded-full object-cover bg-[var(--wl-well)]" />
  <span v-else class="w-full h-full rounded-full grid place-items-center bg-[var(--wl-well)] text-[var(--wl-text-2)] text-sm font-semibold">{{ initials }}</span>
</template>
