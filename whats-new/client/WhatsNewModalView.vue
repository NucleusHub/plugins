<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useRegistry } from '@core/useRegistry.js'
import AppIcon from '@core/AppIcon.vue'
import { Icon } from '@core/icons'
import SparkleIcon from './assets/icons/sparkle.svg?component'

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  announcements: { type: Array, default: () => [] },
  defaultLang: { type: String, default: 'en-US' },
  seenBaseline: { type: [String, Date], default: null },
  optOut: { type: Boolean, default: false },
  preview: { type: Boolean, default: false },
  loaded: { type: Boolean, default: true },
})
const emit = defineEmits(['update:modelValue', 'update:optOut', 'dismiss'])

const { t, locale } = useI18n()
const { apps } = useRegistry()

const isOpen = computed(() => props.modelValue)
const optOutModel = computed({
  get: () => props.optOut,
  set: (v) => emit('update:optOut', v),
})

function pick(field) {
  if (field == null) return ''
  if (typeof field === 'string') return field
  if (typeof field !== 'object') return String(field)
  return field[locale.value] ?? field[props.defaultLang] ?? Object.values(field)[0] ?? ''
}

const latestPublishedAt = computed(() => props.announcements[0]?.publishedAt || null)
const latestNucleusVersion = computed(() => props.announcements[0]?.version || '')

function isUnseen(publishedAt) {
  if (!publishedAt) return false
  const base = props.seenBaseline
  if (!base) return publishedAt === latestPublishedAt.value
  return new Date(publishedAt) > new Date(base)
}

const unseenTabIds = computed(() => {
  const s = new Set()
  for (const a of props.announcements) {
    if (!isUnseen(a.publishedAt)) continue
    for (const e of a.entries || [])
      if ((e.features || []).length) s.add(e.app)
  }
  return s
})

const latestAppIds = computed(() => {
  const s = new Set()
  for (const e of props.announcements[0]?.entries || [])
    if ((e.features || []).length) s.add(e.app)
  return s
})

const tabs = computed(() => {
  const ids = new Set()
  for (const a of props.announcements)
    for (const e of a.entries || [])
      if ((e.features || []).length) ids.add(e.app)

  const order = ['platform', ...apps.value.map(a => a.id)]
  const sorted = [...ids].sort((x, y) => {
    const ix = order.indexOf(x), iy = order.indexOf(y)
    return (ix === -1 ? 999 : ix) - (iy === -1 ? 999 : iy)
  })

  return sorted.map(id => {
    if (id === 'platform') return { id, name: t('core.whatsNew.platformTab'), iconSvg: null }
    const app = apps.value.find(a => a.id === id)
    return { id, name: app?.name || id, iconSvg: app?.iconSvg || null }
  })
})

const defaultTabId = computed(() => {
  const list = tabs.value
  if (!list.length) return null
  const firstUnseen = list.find(tb => unseenTabIds.value.has(tb.id))
  if (firstUnseen) return firstUnseen.id
  const firstLatest = list.find(tb => latestAppIds.value.has(tb.id))
  return (firstLatest || list[0]).id
})

const activeTab = ref(null)
watch(tabs, (list) => {
  if (!list.some(tb => tb.id === activeTab.value)) activeTab.value = defaultTabId.value
}, { immediate: true })
watch(isOpen, (open) => { if (open) activeTab.value = defaultTabId.value })

const activeGroups = computed(() => {
  if (!activeTab.value) return []
  const out = []
  for (const a of props.announcements) {
    const entry = (a.entries || []).find(e => e.app === activeTab.value)
    if (entry && (entry.features || []).length)
      out.push({
        version: entry.version || a.version,
        publishedAt: a.publishedAt,
        features: entry.features,
        unseen: isUnseen(a.publishedAt),
        latest: a.publishedAt === latestPublishedAt.value,
      })
  }
  return out
})

function fmtDate(d) {
  if (!d) return ''
  try { return new Date(d).toLocaleDateString(locale.value, { year: 'numeric', month: 'short', day: 'numeric' }) }
  catch { return '' }
}

function dismiss() {
  emit('update:modelValue', false)
  emit('dismiss')
}

function onKeydown(e) { if (e.key === 'Escape' && isOpen.value) dismiss() }
onMounted(() => window.addEventListener('keydown', onKeydown))
onUnmounted(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <Teleport to="body">
    <Transition name="wn-fade">
      <div v-if="isOpen" class="wn-overlay" @click.self="dismiss">
        <div class="wn-panel" role="dialog" aria-modal="true">
          <div class="wn-header">
            <div class="wn-spark" aria-hidden="true">
              <SparkleIcon width="20" height="20" />
            </div>
            <div class="min-w-0">
              <div class="wn-title-row">
                <h2 class="wn-title">{{ t('core.whatsNew.heading') }}</h2>
                <span v-if="latestNucleusVersion" class="wn-nucleus-badge">Nucleus {{ latestNucleusVersion }}</span>
                <span v-if="preview" class="wn-preview-badge">Preview</span>
              </div>
              <p class="wn-sub">{{ t('core.whatsNew.subheading') }}</p>
            </div>
            <button class="wn-x" @click="dismiss" :aria-label="t('core.whatsNew.close')">
              <Icon width="18" height="18" name="close" :sw="2.2" />
            </button>
          </div>

          <div class="wn-content">
            <div v-if="tabs.length" class="wn-tabs">
              <button
                v-for="tb in tabs" :key="tb.id"
                class="wn-tab" :class="{ 'wn-tab-active': tb.id === activeTab }"
                :title="tb.name"
                @click="activeTab = tb.id"
              >
                <span v-if="tb.id === 'platform'" class="wn-tab-icon" aria-hidden="true">
                  <SparkleIcon width="16" height="16" />
                </span>
                <AppIcon v-else :svg="tb.iconSvg" class="wn-tab-icon" />
                <span class="wn-tab-label">{{ tb.name }}</span>
                <span v-if="unseenTabIds.has(tb.id)" class="wn-tab-dot" aria-hidden="true"></span>
              </button>
            </div>

            <div class="wn-body">
              <p v-if="loaded && !activeGroups.length" class="wn-empty">{{ t('core.whatsNew.emptyState') }}</p>

              <div v-for="g in activeGroups" :key="g.version" class="wn-group"
                   :class="{ 'wn-group-latest': g.unseen || g.latest, 'wn-group-new': g.unseen }">
                <div class="wn-version-row">
                  <span class="wn-version">{{ g.version }}</span>
                  <span v-if="g.unseen" class="wn-new-badge">
                    <span class="wn-new-dot" aria-hidden="true"></span>{{ t('core.whatsNew.newBadge') }}
                  </span>
                  <span v-else-if="g.latest" class="wn-latest-badge">{{ t('core.whatsNew.latestBadge') }}</span>
                  <span v-if="g.publishedAt" class="wn-date">{{ fmtDate(g.publishedAt) }}</span>
                </div>
                <ul class="wn-features">
                  <li v-for="(f, i) in g.features" :key="i" class="wn-feature">
                    <span v-if="f.icon" class="wn-feature-icon" aria-hidden="true">{{ f.icon }}</span>
                    <div class="min-w-0">
                      <p class="wn-feature-title">{{ pick(f.title) }}</p>
                      <p v-if="pick(f.body)" class="wn-feature-body">{{ pick(f.body) }}</p>
                    </div>
                  </li>
                </ul>
              </div>
            </div>
          </div>

          <div class="wn-footer">
            <template v-if="preview">
              <span class="wn-preview-note">Preview only — nothing is saved or shown to users.</span>
              <button class="wn-close-btn" @click="dismiss">Close preview</button>
            </template>
            <template v-else>
              <label class="wn-optout">
                <input type="checkbox" v-model="optOutModel" />
                {{ t('core.whatsNew.dontShowAgain') }}
              </label>
              <button class="wn-close-btn" @click="dismiss">{{ t('core.whatsNew.close') }}</button>
            </template>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.wn-overlay {
  position: fixed;
  inset: 0;
  z-index: 2147482000; /* below the maintenance banner */
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 1rem;
  background: rgba(15, 23, 42, 0.5);
  backdrop-filter: blur(6px);
}

.wn-panel {
  display: flex;
  flex-direction: column;
  width: 100%;
  max-width: 40rem;
  height: min(85vh, 44rem);
  border-radius: 1.25rem;
  overflow: hidden;
  background: rgba(255, 255, 255, 0.85);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow: 0 24px 60px -12px rgba(30, 41, 59, 0.45), 0 0 0 1px rgba(255, 255, 255, 0.25) inset;
  backdrop-filter: blur(20px) saturate(1.3);
  color: #0f172a;
}

.wn-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1.1rem 1.25rem 0.9rem;
  border-bottom: 1px solid rgba(15, 23, 42, 0.08);
}
.wn-spark {
  flex: none;
  display: grid;
  place-items: center;
  width: 2.25rem;
  height: 2.25rem;
  border-radius: 0.75rem;
  color: #fff;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
}
.wn-title-row { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
.wn-title { font-weight: 700; font-size: 1.02rem; line-height: 1.2; }
.wn-nucleus-badge {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  color: #fff;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  padding: 0.1rem 0.45rem;
  border-radius: 0.4rem;
}
.wn-preview-badge {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.02em;
  color: #92400e;
  background: rgba(245, 158, 11, 0.2);
  border: 1px solid rgba(245, 158, 11, 0.4);
  padding: 0.1rem 0.45rem;
  border-radius: 0.4rem;
}
.wn-sub { font-size: 0.8rem; opacity: 0.6; margin-top: 1px; }
.wn-x {
  margin-left: auto;
  flex: none;
  padding: 0.35rem;
  border-radius: 0.6rem;
  color: rgba(15, 23, 42, 0.45);
  cursor: pointer;
  transition: background 0.13s, color 0.13s;
}
.wn-x:hover { background: rgba(15, 23, 42, 0.06); color: #0f172a; }

.wn-content {
  display: flex;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.wn-tabs {
  flex: none;
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  width: 11rem;
  padding: 0.75rem 0.6rem;
  overflow-y: auto;
  border-right: 1px solid rgba(15, 23, 42, 0.1);
}
.wn-tab {
  position: relative;
  flex: none;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  width: 100%;
  padding: 0.5rem 0.6rem;
  border-radius: 0.6rem;
  border-left: 2px solid transparent;
  font-size: 0.82rem;
  font-weight: 600;
  text-align: left;
  color: rgba(15, 23, 42, 0.55);
  cursor: pointer;
  transition: color 0.13s, background 0.13s;
}
.wn-tab:hover { color: #1e293b; background: rgba(15, 23, 42, 0.05); }
.wn-tab-active {
  color: #4f46e5;
  background: rgba(99, 102, 241, 0.1);
}
.wn-tab-icon { width: 1rem; height: 1rem; flex: none; }

.wn-tab-dot {
  margin-left: auto;
  flex: none;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  box-shadow: 0 0 0 0 rgba(139, 92, 246, 0.55);
  animation: wn-pulse 1.9s cubic-bezier(0.4, 0, 0.2, 1) infinite;
}
@keyframes wn-pulse {
  0%   { box-shadow: 0 0 0 0 rgba(139, 92, 246, 0.55); }
  70%  { box-shadow: 0 0 0 7px rgba(139, 92, 246, 0); }
  100% { box-shadow: 0 0 0 0 rgba(139, 92, 246, 0); }
}

.wn-body {
  flex: 1;
  min-width: 0;
  overflow-y: auto;
  padding: 1rem 1.25rem 0.5rem;
}
.wn-empty { text-align: center; font-size: 0.9rem; opacity: 0.55; padding: 2.5rem 0; }

.wn-group { margin-bottom: 1.25rem; }
.wn-group-latest {
  position: relative;
  margin: 0 -0.75rem 1.25rem;
  padding: 0.85rem 0.9rem 0.95rem;
  border-radius: 0.85rem;
  background: linear-gradient(135deg, rgba(99, 102, 241, 0.09), rgba(139, 92, 246, 0.06));
  border: 1px solid rgba(99, 102, 241, 0.22);
  box-shadow: 0 1px 3px rgba(99, 102, 241, 0.12);
}
.wn-group-new {
  border-color: rgba(99, 102, 241, 0.4);
  background: linear-gradient(135deg, rgba(99, 102, 241, 0.16), rgba(139, 92, 246, 0.1));
  animation: wn-glow 3.2s ease-in-out infinite;
}
@keyframes wn-glow {
  0%, 100% { box-shadow: 0 1px 3px rgba(99, 102, 241, 0.12), 0 0 0 0 rgba(139, 92, 246, 0.18); }
  50%      { box-shadow: 0 1px 3px rgba(99, 102, 241, 0.12), 0 0 22px 2px rgba(139, 92, 246, 0.22); }
}

.wn-version-row { display: flex; align-items: baseline; gap: 0.6rem; margin-bottom: 0.6rem; }
.wn-latest-badge {
  font-size: 0.62rem;
  font-weight: 800;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: #fff;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  padding: 0.12rem 0.45rem;
  border-radius: 0.4rem;
}
.wn-new-badge {
  position: relative;
  display: inline-flex;
  align-items: center;
  gap: 0.28rem;
  overflow: hidden;
  font-size: 0.62rem;
  font-weight: 800;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: #fff;
  background: linear-gradient(135deg, #6366f1, #8b5cf6);
  padding: 0.14rem 0.5rem;
  border-radius: 0.4rem;
  box-shadow: 0 2px 8px rgba(139, 92, 246, 0.35);
}
.wn-new-badge::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(115deg, transparent 30%, rgba(255, 255, 255, 0.55) 50%, transparent 70%);
  transform: translateX(-120%);
  animation: wn-shimmer 2.6s ease-in-out infinite;
}
@keyframes wn-shimmer {
  0%, 55% { transform: translateX(-120%); }
  100%    { transform: translateX(120%); }
}
.wn-new-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 0 4px rgba(255, 255, 255, 0.9);
}
.wn-version {
  font-size: 0.7rem;
  font-weight: 800;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: #4f46e5;
  background: rgba(99, 102, 241, 0.12);
  padding: 0.15rem 0.5rem;
  border-radius: 0.4rem;
}
.wn-date { font-size: 0.72rem; opacity: 0.5; }

.wn-features { display: flex; flex-direction: column; gap: 0.7rem; }
.wn-feature { display: flex; gap: 0.7rem; align-items: flex-start; }
.wn-feature-icon {
  flex: none;
  display: grid;
  place-items: center;
  width: 1.9rem;
  height: 1.9rem;
  border-radius: 0.55rem;
  font-size: 1rem;
  background: rgba(15, 23, 42, 0.05);
}
.wn-feature-title { font-weight: 600; font-size: 0.9rem; line-height: 1.3; }
.wn-feature-body { font-size: 0.82rem; opacity: 0.7; line-height: 1.4; margin-top: 1px; }

.wn-footer {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.85rem 1.25rem;
  border-top: 1px solid rgba(15, 23, 42, 0.08);
}
.wn-optout {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.8rem;
  opacity: 0.7;
  cursor: pointer;
}
.wn-optout input { cursor: pointer; accent-color: #6366f1; }
.wn-preview-note { font-size: 0.78rem; opacity: 0.6; }
.wn-close-btn {
  margin-left: auto;
  padding: 0.5rem 1.1rem;
  border-radius: 0.7rem;
  font-size: 0.85rem;
  font-weight: 600;
  color: #fff;
  background: #4f46e5;
  cursor: pointer;
  transition: background 0.13s;
}
.wn-close-btn:hover { background: #4338ca; }

.dark .wn-panel {
  background: rgba(15, 23, 42, 0.9);
  border-color: rgba(255, 255, 255, 0.1);
  color: #f1f5f9;
  box-shadow: 0 24px 60px -12px rgba(0, 0, 0, 0.6), 0 0 0 1px rgba(255, 255, 255, 0.06) inset;
}
.dark .wn-header,
.dark .wn-footer { border-color: rgba(255, 255, 255, 0.1); }
.dark .wn-sub,
.dark .wn-date,
.dark .wn-empty,
.dark .wn-feature-body,
.dark .wn-optout,
.dark .wn-preview-note { opacity: 0.6; }
.dark .wn-preview-badge {
  color: #fcd34d;
  background: rgba(245, 158, 11, 0.16);
  border-color: rgba(245, 158, 11, 0.35);
}
.dark .wn-x { color: rgba(255, 255, 255, 0.5); }
.dark .wn-x:hover { background: rgba(255, 255, 255, 0.1); color: #fff; }
.dark .wn-tabs { border-right-color: rgba(255, 255, 255, 0.1); }
.dark .wn-tab { color: rgba(255, 255, 255, 0.55); }
.dark .wn-tab:hover { color: #fff; background: rgba(255, 255, 255, 0.08); }
.dark .wn-tab-active { color: #a5b4fc; background: rgba(99, 102, 241, 0.22); }
.dark .wn-version { color: #a5b4fc; background: rgba(99, 102, 241, 0.2); }
.dark .wn-group-latest {
  background: linear-gradient(135deg, rgba(99, 102, 241, 0.18), rgba(139, 92, 246, 0.12));
  border-color: rgba(129, 140, 248, 0.35);
  box-shadow: none;
}
.dark .wn-group-new {
  background: linear-gradient(135deg, rgba(99, 102, 241, 0.26), rgba(139, 92, 246, 0.18));
  border-color: rgba(129, 140, 248, 0.5);
}
.dark .wn-feature-icon { background: rgba(255, 255, 255, 0.08); }

@media (max-width: 640px) {
  .wn-panel { height: min(92vh, 44rem); border-radius: 1rem; }
  .wn-tabs {
    width: auto;
    padding: 0.6rem 0.4rem;
    gap: 0.3rem;
  }
  .wn-tab {
    width: 2.5rem;
    height: 2.5rem;
    justify-content: center;
    padding: 0;
    gap: 0;
    border-left: none;
    border-radius: 0.7rem;
  }
  .wn-tab-label { display: none; }
  .wn-tab-icon { width: 1.15rem; height: 1.15rem; }
  .wn-body { padding: 0.9rem 1rem 0.5rem; }
  .wn-tab-dot {
    position: absolute;
    top: 0.35rem;
    right: 0.35rem;
    margin-left: 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .wn-tab-dot,
  .wn-group-new,
  .wn-new-badge::after { animation: none; }
}

@media (max-width: 380px) {
  .wn-footer { flex-wrap: wrap; gap: 0.6rem; padding: 0.75rem 1rem; }
  .wn-close-btn { width: 100%; margin-left: 0; }
}

.wn-fade-enter-active, .wn-fade-leave-active { transition: opacity 0.2s ease; }
.wn-fade-enter-active .wn-panel, .wn-fade-leave-active .wn-panel { transition: transform 0.2s ease, opacity 0.2s ease; }
.wn-fade-enter-from, .wn-fade-leave-to { opacity: 0; }
.wn-fade-enter-from .wn-panel, .wn-fade-leave-to .wn-panel { transform: translateY(12px) scale(0.98); opacity: 0; }
</style>
