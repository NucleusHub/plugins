import { ref } from 'vue'

// Shared open-state for the What's New changelog modal. The modal is mounted once
// in AuthGuard and decides on its own whether to auto-open on login; the sidebar
// launcher (and anything else) can force it open via open(). Module-singleton so
// both sides share one reactive flag. See core/WhatsNewModal.vue.
const isOpen = ref(false)

export function useWhatsNew() {
  return {
    isOpen,
    open: () => { isOpen.value = true },
    close: () => { isOpen.value = false },
  }
}
