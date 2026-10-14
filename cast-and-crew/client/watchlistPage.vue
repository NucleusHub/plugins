<script setup>
import PersonPage from './PersonPage.vue'
import CreditsPage from './CreditsPage.vue'

// `page` is 'person' (arg: TMDb person id) or 'credits' (arg: `movie:603:Title`).
defineProps({
  page: { type: String, required: true },
  arg: { type: String, default: '' },
  host: { type: Object, required: true },
})
</script>

<template>
  <PersonPage v-if="page === 'person'" :person-id="Number(arg) || 0" :host="host" />
  <CreditsPage v-else-if="page === 'credits'" :arg="arg" :host="host" />
</template>
