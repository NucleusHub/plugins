<script setup>
// Non-dismissable maintenance alert, shown across every Nucleus app.
//
// The signal is a static JSON file (`/maintenance.json`) served by nginx — NOT
// an app API or socket. That's deliberate: during a rebuild the app servers are
// the thing going down, but nginx (and this static file) stays up, so the banner
// keeps showing for the whole outage. Flip it with `infra/maintenance on|off`.
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useI18n } from '@core/useI18n.js'
import AlertTriangleIcon from './assets/icons/alert-triangle.svg?component'

const POLL_MS = 8000

const { t, locale } = useI18n()

const active = ref(false)
const flag = ref(null)
let timer = null

// The flag carries title/message either as a plain string (legacy infra CLI) or
// as a { lang: text } map (admin console, translated per language). Resolve to
// the viewer's locale, then the flag's default language, then any value.
function pick(field) {
  if (field == null) return ''
  if (typeof field === 'string') return field
  if (typeof field !== 'object') return String(field)
  return field[locale.value] ?? field[flag.value?.defaultLang] ?? Object.values(field)[0] ?? ''
}

const title = computed(() => pick(flag.value?.title) || t('core.maintenance.title'))
const message = computed(() => pick(flag.value?.message) || t('core.maintenance.defaultMessage'))

async function poll() {
  try {
    const res = await fetch('/maintenance.json', { cache: 'no-store' })
    if (!res.ok) { active.value = false; return }   // 204/404 → not in maintenance
    const data = await res.json()
    active.value = !!data.active
    flag.value = data
  } catch {
    // Explicit-flag-only: a failed fetch is NOT treated as maintenance, so a
    // transient blip never flashes the banner.
    active.value = false
  }
}

onMounted(() => {
  poll()
  timer = setInterval(poll, POLL_MS)
})
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<template>
  <Transition name="mnt-fade">
    <div v-if="active" class="mnt-banner" role="alert" aria-live="assertive">
      <div class="mnt-inner">
        <span class="mnt-pulse" aria-hidden="true">
          <AlertTriangleIcon width="22" height="22" />
        </span>
        <div class="mnt-text">
          <p class="mnt-title">{{ title }}</p>
          <p class="mnt-msg">{{ message }}</p>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.mnt-banner {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 2147483000; /* above every app modal/overlay */
  display: flex;
  justify-content: center;
  padding: 0.75rem 1rem calc(0.75rem + env(safe-area-inset-bottom, 0px));
  pointer-events: none; /* let clicks pass through the gutter, not the pill */
}

.mnt-inner {
  pointer-events: auto;
  display: flex;
  align-items: center;
  gap: 0.85rem;
  max-width: 44rem;
  width: 100%;
  padding: 0.7rem 1.1rem;
  border-radius: 1rem;
  color: #451a03;
  background: linear-gradient(135deg, rgba(253, 230, 138, 0.92), rgba(251, 191, 36, 0.92));
  border: 1px solid rgba(180, 83, 9, 0.45);
  box-shadow: 0 10px 30px -6px rgba(120, 53, 15, 0.5), 0 0 0 1px rgba(255, 255, 255, 0.25) inset;
  backdrop-filter: blur(14px) saturate(1.4);
}

.mnt-pulse {
  flex: none;
  display: grid;
  place-items: center;
  width: 2.25rem;
  height: 2.25rem;
  border-radius: 0.75rem;
  color: #7c2d12;
  background: rgba(255, 255, 255, 0.4);
  animation: mnt-pulse 1.8s ease-in-out infinite;
}

@keyframes mnt-pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50%      { opacity: 0.65; transform: scale(0.92); }
}

.mnt-text { min-width: 0; line-height: 1.25; }
.mnt-title { font-weight: 700; font-size: 0.9rem; letter-spacing: 0.01em; }
.mnt-msg   { font-size: 0.82rem; opacity: 0.85; margin-top: 1px; }

.mnt-fade-enter-active,
.mnt-fade-leave-active { transition: opacity 0.3s ease, transform 0.3s ease; }
.mnt-fade-enter-from,
.mnt-fade-leave-to { opacity: 0; transform: translateY(1rem); }

@media (prefers-reduced-motion: reduce) {
  .mnt-pulse { animation: none; }
}
</style>
