<script setup>
import { ref, watch } from 'vue'
import { lookup } from './useInCommon.js'
import InCommonBadge from './InCommonBadge.vue'

// Watchlist item indicator. The host (ItemCard.vue) renders this in the card
// meta row and passes the WatchlistItem as `item`; we derive the lookup payload
// and hand the resolved profiles to the shared badge.
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
