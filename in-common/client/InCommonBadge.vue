<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import AvatarCircle from '@core/auth/AvatarCircle.vue'

const props = defineProps({
  profiles: { type: Array, default: () => [] },
  context: { type: String, default: 'watchlist' },
  variant: { type: String, default: 'default' },
})

const POP_WIDTH = 220
const CLOSE_DELAY = 130

const open = ref(false)
const chipRef = ref(null)
const popRef = ref(null)
const popStyle = ref({})
let closeTimer = null

const count = computed(() => props.profiles.length)
const NOUN = { shelf: 'this book', dex: 'this card', 'dex-binder': 'this card' }
const heading = computed(() => {
  if (props.context === 'dex-binder') {
    const who = count.value === 1 ? 'member' : 'members'
    return `Already in this binder — ${count.value} ${who} have this card`
  }
  const who = count.value === 1 ? 'person also has' : 'people also have'
  return `${count.value} ${who} ${NOUN[props.context] ?? 'this title'}`
})

const asProfile = (p) => ({
  _id: p.profileId,
  name: p.name,
  color: p.color,
  emoji: p.emoji,
  hasImage: p.hasImage,
  imageUpdatedAt: p.imageUpdatedAt,
  role: p.role,
})

function updatePos() {
  const el = chipRef.value
  if (!el) return
  const r = el.getBoundingClientRect()
  const left = Math.min(Math.max(8, r.left), window.innerWidth - POP_WIDTH - 8)
  const above = r.top > 240
  popStyle.value = above
    ? { left: `${left}px`, top: `${r.top - 6}px`, transform: 'translateY(-100%)' }
    : { left: `${left}px`, top: `${r.bottom + 6}px` }
}

function openNow() {
  clearTimeout(closeTimer)
  updatePos()
  open.value = true
}
function scheduleClose() {
  clearTimeout(closeTimer)
  closeTimer = setTimeout(() => { open.value = false }, CLOSE_DELAY)
}
function cancelClose() {
  clearTimeout(closeTimer)
}
function toggle() {
  if (open.value) { open.value = false; clearTimeout(closeTimer) }
  else openNow()
}

watch(open, (v) => {
  const method = v ? 'addEventListener' : 'removeEventListener'
  window[method]('scroll', updatePos, true)
  window[method]('resize', updatePos)
})

onBeforeUnmount(() => {
  clearTimeout(closeTimer)
  window.removeEventListener('scroll', updatePos, true)
  window.removeEventListener('resize', updatePos)
})
</script>

<template>
  <div v-if="count" class="ic-root">
    <button
      ref="chipRef"
      type="button"
      class="ic-chip"
      :class="{ 'ic-overlay': variant === 'overlay' }"
      :title="heading"
      :aria-label="heading"
      @mouseenter="openNow"
      @mouseleave="scheduleClose"
      @focus="openNow"
      @blur="scheduleClose"
      @click.stop="toggle"
    >
      <svg class="ic-glyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <circle cx="9" cy="8" r="3.1" />
        <path d="M3.6 18.5a5.4 5.4 0 0 1 10.8 0" />
        <path d="M16.2 5.3a2.9 2.9 0 0 1 0 5.5" />
        <path d="M17.7 13a5.4 5.4 0 0 1 2.7 4.4" />
      </svg>
      <span class="ic-count">{{ count }}</span>
    </button>

    <Teleport to="body">
      <div
        v-if="open"
        ref="popRef"
        class="ic-pop"
        :style="popStyle"
        @mouseenter="cancelClose"
        @mouseleave="scheduleClose"
      >
        <p class="ic-pop-head">{{ heading }}</p>
        <ul class="ic-pop-list">
          <li v-for="p in profiles" :key="p.profileId" class="ic-pop-row">
            <AvatarCircle :profile="asProfile(p)" :size="24" />
            <span class="ic-pop-name">{{ p.name }}</span>
          </li>
        </ul>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.ic-root {
  display: inline-flex;
}

.ic-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px 2px 6px;
  border-radius: 9999px;
  cursor: default;
  font-size: 0.72rem;
  line-height: 1;
  font-weight: 700;
  color: rgb(79 70 229);
  background: linear-gradient(180deg, rgb(99 102 241 / 0.16), rgb(99 102 241 / 0.1));
  border: 1px solid rgb(99 102 241 / 0.28);
  box-shadow: 0 1px 2px rgb(15 23 42 / 0.06);
  transition: background 0.15s ease, border-color 0.15s ease, transform 0.15s ease, box-shadow 0.15s ease;
}
.ic-chip:hover {
  background: linear-gradient(180deg, rgb(99 102 241 / 0.26), rgb(99 102 241 / 0.16));
  border-color: rgb(99 102 241 / 0.45);
  transform: translateY(-0.5px);
  box-shadow: 0 2px 6px rgb(79 70 229 / 0.18);
}
:global(.dark) .ic-chip {
  color: rgb(199 210 254);
  background: linear-gradient(180deg, rgb(129 140 248 / 0.24), rgb(129 140 248 / 0.14));
  border-color: rgb(129 140 248 / 0.35);
}
:global(.dark) .ic-chip:hover {
  background: linear-gradient(180deg, rgb(129 140 248 / 0.34), rgb(129 140 248 / 0.2));
  border-color: rgb(129 140 248 / 0.5);
}

.ic-chip.ic-overlay,
:global(.dark) .ic-chip.ic-overlay {
  color: #fff;
  background: rgb(0 0 0 / 0.5);
  border-color: rgb(255 255 255 / 0.28);
  backdrop-filter: blur(4px);
  box-shadow: 0 1px 3px rgb(0 0 0 / 0.4);
}
.ic-chip.ic-overlay:hover,
:global(.dark) .ic-chip.ic-overlay:hover {
  background: rgb(0 0 0 / 0.66);
  border-color: rgb(255 255 255 / 0.4);
}

.ic-glyph {
  width: 13px;
  height: 13px;
  flex-shrink: 0;
}
.ic-count {
  font-variant-numeric: tabular-nums;
}
</style>

<style>
/* Teleported to <body>, so these styles can't be scoped. */
.ic-pop {
  position: fixed;
  z-index: 60;
  width: 220px;
  max-height: 240px;
  overflow-y: auto;
  padding: 10px;
  border-radius: 14px;
  background: rgb(255 255 255 / 0.96);
  backdrop-filter: blur(14px);
  border: 1px solid rgb(148 163 184 / 0.3);
  box-shadow: 0 12px 34px rgb(15 23 42 / 0.28);
  animation: ic-pop-in 0.12s ease-out;
}
.dark .ic-pop {
  background: rgb(30 41 59 / 0.96);
  border-color: rgb(148 163 184 / 0.2);
}
/* Opacity only: transform is used for positioning. */
@keyframes ic-pop-in {
  from { opacity: 0; }
}
.ic-pop-head {
  font-size: 0.68rem;
  font-weight: 700;
  margin: 0 0 8px;
  color: rgb(100 116 139);
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.dark .ic-pop-head {
  color: rgb(148 163 184);
}
.ic-pop-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 7px;
}
.ic-pop-row {
  display: flex;
  align-items: center;
  gap: 9px;
}
.ic-pop-name {
  font-size: 0.82rem;
  font-weight: 500;
  color: rgb(30 41 59);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.dark .ic-pop-name {
  color: rgb(226 232 240);
}
</style>
