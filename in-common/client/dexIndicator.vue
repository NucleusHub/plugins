<script setup>
import { ref, watch, computed } from 'vue'
import { lookup } from './useInCommon.js'
import InCommonBadge from './InCommonBadge.vue'

const props = defineProps({
  card: { type: Object, required: true },
  variant: { type: String, default: 'tile' },
  binderId: { type: String, default: '' },
})

const profiles = ref([])

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
