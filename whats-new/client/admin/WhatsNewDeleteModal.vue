<script setup>
import { ref, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { Icon } from '@core/icons'

// Confirm + delete a "What's New" announcement. Mirrors the other admin delete
// modals (UserDeleteModal, GroupDeleteModal) instead of a native confirm().
const props = defineProps({
  announcement: { type: Object, default: null },
})
const emit = defineEmits(['close', 'deleted'])

const busy = ref(false)
const error = ref(null)

watch(() => props.announcement, () => {
  busy.value = false
  error.value = null
}, { immediate: true })

async function confirm() {
  if (!props.announcement || busy.value) return
  busy.value = true
  error.value = null
  try {
    const res = await fetch(`/api/auth/whats-new/announcements/${props.announcement._id}`, {
      method: 'DELETE',
      credentials: 'include',
    })
    if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`)
    emit('deleted', props.announcement._id)
    emit('close')
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <TemplateModal :show="!!announcement" size="md" @cancel="busy || emit('close')">
    <div class="p-5 flex flex-col gap-4">
      <div>
        <h2 class="text-[15px] font-bold text-slate-900 dark:text-white">Delete “{{ announcement?.version }}”?</h2>
        <p class="text-xs text-slate-500 dark:text-white/45 mt-1">
          This removes the announcement and its release notes for every app and language.
        </p>
      </div>

      <!-- Hard warning -->
      <div class="flex items-start gap-2.5 rounded-xl bg-red-500/10 border border-red-500/30 px-3.5 py-2.5">
        <Icon name="warningTriangle" class="w-4 h-4 mt-0.5 shrink-0 text-red-500" />
        <p class="text-xs font-medium text-red-700 dark:text-red-300 leading-relaxed">
          <strong>This cannot be undone.</strong>
        </p>
      </div>

      <p v-if="error" class="text-xs text-red-500">{{ error }}</p>

      <div class="flex gap-3 justify-end">
        <button
          class="px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg cursor-pointer transition-colors disabled:opacity-60"
          :disabled="busy"
          @click="emit('close')"
        >Cancel</button>
        <button
          class="px-4 py-2 text-sm font-medium text-white bg-red-600 hover:bg-red-500 rounded-lg cursor-pointer transition-colors disabled:opacity-60"
          :disabled="busy"
          @click="confirm"
        >{{ busy ? 'Deleting…' : 'Delete announcement' }}</button>
      </div>
    </div>
  </TemplateModal>
</template>
