<script setup>
import { ref } from 'vue'
import { useI18n } from '@core/useI18n.js'
import { useAuth } from '@core/auth/useAuth.js'

const props = defineProps({
  profile: { type: Object, required: true },
})
const emit = defineEmits(['updated'])

const { t } = useI18n()
const { authFetch, checkSession } = useAuth()

const showUpdates = ref(!(props.profile.whatsNew?.optOut))
const saving = ref(false)

async function toggle() {
  const next = !showUpdates.value
  showUpdates.value = next
  saving.value = true
  try {
    const res = await authFetch('/api/auth/whats-new/opt-out', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ optOut: !next }),
    })
    if (!res.ok) throw new Error()
    await checkSession()
    emit('updated')
  } catch {
    showUpdates.value = !next
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="flex items-center justify-between gap-3">
    <div class="min-w-0">
      <p class="text-xs font-medium text-slate-700 dark:text-white/70">{{ t('core.whatsNew.showUpdates') }}</p>
      <p class="text-[11px] text-slate-400 dark:text-white/40 mt-0.5">{{ t('core.whatsNew.showUpdatesHint') }}</p>
    </div>
    <button
      type="button" role="switch" :aria-checked="showUpdates" :disabled="saving"
      class="relative shrink-0 w-10 h-6 rounded-full transition-colors cursor-pointer disabled:opacity-50"
      :class="showUpdates ? 'bg-indigo-600' : 'bg-slate-300 dark:bg-white/15'"
      @click="toggle"
    >
      <span
        class="absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform"
        :class="showUpdates ? 'translate-x-4' : ''"
      />
    </button>
  </div>
</template>
