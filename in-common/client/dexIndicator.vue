<script setup>
import { ref, watch, computed } from 'vue'
import { lookup } from './useInCommon.js'
import InCommonBadge from './InCommonBadge.vue'

// Dex card indicator. The hosts (CardTile.vue on the grid, CardDetailModal.vue
// in the detail view) pass the catalog card as `card`.
//
// Two questions, chosen by whether a `binderId` is in play:
//   • no binder — "who else in your group/network has this card?"
//   • in a shared binder — "is this card already in this binder's collection?"
// Same batching, same badge; only the scope of the audience changes.
const props = defineProps({
  card: { type: Object, required: true },
  // 'tile'   — sits on top of the artwork in the grid  → dark glass
  // 'detail' — inside the card detail panel            → indigo tint
  variant: { type: String, default: 'tile' },
  // When set, the lookup is scoped to that shared binder's members.
  binderId: { type: String, default: '' },
})

const profiles = ref([])

// Dex cards are globally identified, so the card id IS the match key — no fuzzy
// title matching the way watchlist and shelf need.
async function run() {
  const cardId = props.card?.cardId
  if (!cardId) {
    profiles.value = []
    return
  }
  profiles.value = await lookup(
    'dex',
    { key: cardId, cardId },
    props.binderId ? { binderId: props.binderId } : null
  )
}

watch(() => [props.card?.cardId, props.binderId], run, { immediate: true })

const badgeVariant = computed(() => (props.variant === 'tile' ? 'overlay' : 'default'))
const context = computed(() => (props.binderId ? 'dex-binder' : 'dex'))
</script>

<template>
  <InCommonBadge :profiles="profiles" :context="context" :variant="badgeVariant" />
</template>
