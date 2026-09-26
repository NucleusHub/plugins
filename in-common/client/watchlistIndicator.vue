<script setup>
import { ref, watch } from 'vue'
import { lookup } from './useInCommon.js'
import InCommonBadge from './InCommonBadge.vue'

const props = defineProps({
  item: { type: Object, required: true },
  variant: { type: String, default: 'default' },
})

const profiles = ref([])

async function run(item) {
  const key = item?._id || item?.id
  if (!key || !item.title) {
    profiles.value = []
    return
  }
  profiles.value = await lookup('watchlist', {
    key,
    tmdbId: item.tmdbId,
    title: item.title,
    type: item.type,
  })
}

watch(() => props.item?._id || props.item?.id, () => run(props.item), { immediate: true })
</script>

<template>
  <InCommonBadge :profiles="profiles" context="watchlist" :variant="variant" />
</template>
