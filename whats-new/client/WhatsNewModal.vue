<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuth } from '@core/auth/useAuth.js'
import { useWhatsNew } from './useWhatsNew.js'
import { burst } from '@core/confetti.js'
import WhatsNewModalView from './WhatsNewModalView.vue'

const { profile, authFetch } = useAuth()
const { isOpen, open } = useWhatsNew()

const announcements = ref([])
const defaultLang = ref('en-US')
const loaded = ref(false)
const optOutChecked = ref(false)
const seenBaseline = ref(null)

const latestPublishedAt = computed(() => announcements.value[0]?.publishedAt || null)

function maybeAutoOpen() {
  const wn = profile.value?.whatsNew || {}
  optOutChecked.value = !!wn.optOut
  seenBaseline.value = wn.lastSeenAt || null
  if (wn.optOut) return
  const latest = latestPublishedAt.value
  if (!latest) return
  if (!wn.lastSeenAt || new Date(latest) > new Date(wn.lastSeenAt)) {
    open()
    setTimeout(() => burst({ origin: { x: 0.5, y: 0.3 }, particleCount: 70, spread: 100 }), 340)
  }
}

async function load() {
  try {
    const res = await authFetch('/api/auth/whats-new/feed')
    if (!res.ok) return
    const data = await res.json()
    announcements.value = data.announcements || []
    defaultLang.value = data.defaultLanguage || 'en-US'
  } catch {
  } finally {
    loaded.value = true
    maybeAutoOpen()
  }
}
onMounted(load)

async function dismiss() {
  seenBaseline.value = new Date().toISOString()
  try {
    await authFetch('/api/auth/whats-new/seen', { method: 'POST' })
    await authFetch('/api/auth/whats-new/opt-out', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ optOut: optOutChecked.value }),
    })
  } catch {}
}
</script>

<template>
  <WhatsNewModalView
    v-model="isOpen"
    v-model:opt-out="optOutChecked"
    :announcements="announcements"
    :default-lang="defaultLang"
    :seen-baseline="seenBaseline"
    :loaded="loaded"
    @dismiss="dismiss"
  />
</template>
