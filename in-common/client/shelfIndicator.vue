<script setup>
import { ref, watch } from 'vue'
import { lookup } from './useInCommon.js'
import InCommonBadge from './InCommonBadge.vue'

const props = defineProps({
  entry: { type: Object, required: true },
  variant: { type: String, default: 'default' },
})

const profiles = ref([])

async function run(entry) {
  const key = entry?.id || entry?._id
  const book = entry?.book || {}
  if (!key || (!book.isbn && !book.title && !book.identifiers)) {
    profiles.value = []
    return
  }
  profiles.value = await lookup('shelf', {
    key,
    isbn: book.isbn,
    identifiers: book.identifiers,
    title: book.title,
    authors: book.authors,
  })
}

watch(() => props.entry?.id || props.entry?._id, () => run(props.entry), { immediate: true })
</script>

<template>
  <InCommonBadge :profiles="profiles" context="shelf" :variant="variant" />
</template>
