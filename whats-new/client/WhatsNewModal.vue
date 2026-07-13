<script setup>
// The live "What's New" changelog modal. Mounted once in AuthGuard (authenticated
// branch). Fetches the published feed, decides whether to auto-open on login
// (something published since the viewer last dismissed it — profile.whatsNew.
// lastSeenAt), and persists seen/opt-out state on dismiss. All rendering lives in
// the shared WhatsNewModalView.vue, which the Admin preview reuses so the preview
// is byte-for-byte what users see. Backend: plugins/whats-new/server/route.js.
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
// The viewer's lastSeenAt captured at load time. Anything published after this is
// "new to you". Frozen at load so the highlights stay stable while the modal is
// open, then bumped on dismiss so a re-open in the same session shows caught up.
const seenBaseline = ref(null)

const latestPublishedAt = computed(() => announcements.value[0]?.publishedAt || null)

// Auto-open once the feed and profile are both known: unless opted out, open when
// an announcement was published more recently than the viewer last dismissed it
// (a never-seen profile with lastSeenAt=null still opens — but new profiles are
// seeded to "now" server-side, so they start caught up).
function maybeAutoOpen() {
  const wn = profile.value?.whatsNew || {}
  optOutChecked.value = !!wn.optOut
  seenBaseline.value = wn.lastSeenAt || null
  if (wn.optOut) return
  const latest = latestPublishedAt.value
  if (!latest) return
  if (!wn.lastSeenAt || new Date(latest) > new Date(wn.lastSeenAt)) {
    open()
    // A quiet welcome flourish for a brand-new release — fires once, only on the
    // auto-open (never on a manual sidebar open or when the viewer is caught up),
    // after the modal has animated in. No-op under prefers-reduced-motion.
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
    // Silent: a failed feed simply means no modal.
  } finally {
    loaded.value = true
    maybeAutoOpen()
  }
}
onMounted(load)

// The view closes itself via v-model; here we just persist the dismissal.
async function dismiss() {
  // Mark as caught up locally so a same-session re-open drops the NEW highlights
  // (the server records lastSeenAt below; the local profile isn't refetched).
  seenBaseline.value = new Date().toISOString()
  try {
    await authFetch('/api/auth/whats-new/seen', { method: 'POST' })
    // Always send the checkbox state so it can both opt out and re-enable.
    await authFetch('/api/auth/whats-new/opt-out', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ optOut: optOutChecked.value }),
    })
  } catch { /* best effort */ }
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
