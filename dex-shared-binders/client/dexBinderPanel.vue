<script setup>
import { ref, watch, computed } from 'vue'
import AvatarCircle from '@core/auth/AvatarCircle.vue'
import { Icon, Spinner } from '@core/icons'

// The share panel, mounted by Dex inside a binder's own settings dialog (Dex
// globs `client/dexBinderPanel.vue` from plugins targeting `dex`, then renders
// it under a "Sharing" tab). Everything sharing-related lives here, so removing
// the plugin removes the whole surface with it.
//
// Roles read as what they let you do, not as abstract tiers — the description
// under each is the actual capability, matching Dex's binderAccess table.
const props = defineProps({
  binder: { type: Object, default: null },
})
const emit = defineEmits(['saved'])

const API = '/api/dex/x/dex-shared-binders'

const ROLES = [
  { key: 'viewer', label: 'Viewer', hint: 'Can open the binder and look through its pages.' },
  { key: 'contributor', label: 'Contributor', hint: 'Can also slot cards in and take them out.' },
  { key: 'admin', label: 'Admin', hint: 'Can also rename it, change the cover and share it on.' },
]

const loading = ref(false)
const saving = ref(false)
const error = ref('')
const data = ref(null)
// Working copy: [{ profileId, name, …, grant }]. Saved as a whole list.
const shares = ref([])
const adding = ref(false)
const search = ref('')

const canManage = computed(() => !!data.value?.canManage)
const candidates = computed(() => {
  const q = search.value.trim().toLowerCase()
  const chosen = new Set(shares.value.map((s) => s.profileId))
  return (data.value?.candidates ?? [])
    .filter((c) => !chosen.has(c.profileId))
    .filter((c) => !q || c.name.toLowerCase().includes(q))
    .slice(0, 40)
})

async function load() {
  if (!props.binder?.id) return
  loading.value = true
  error.value = ''
  try {
    const res = await fetch(`${API}/binders/${props.binder.id}/shares`, { credentials: 'include' })
    if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`)
    data.value = await res.json()
    shares.value = [...(data.value.shares ?? [])]
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function persist() {
  saving.value = true
  error.value = ''
  try {
    const res = await fetch(`${API}/binders/${props.binder.id}/shares`, {
      method: 'PUT',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ shares: shares.value.map((s) => ({ profileId: s.profileId, role: s.grant })) }),
    })
    if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`)
    // The binder's `shared` flag may have flipped, which changes how it renders
    // in the list — let the host refresh it.
    emit('saved', { ...props.binder, shared: shares.value.length > 0 || !!data.value?.group })
  } catch (e) {
    error.value = e.message
    await load() // don't leave the panel showing a state the server rejected
  } finally {
    saving.value = false
  }
}

// Contributor, not viewer: adding a person to a binder means letting them slot
// cards in and out — that's the point of sharing one. Dropping to Viewer is the
// deliberate act, so it's the dropdown's job, not the default's.
function addPerson(person) {
  shares.value = [...shares.value, { ...person, grant: 'contributor' }]
  adding.value = false
  search.value = ''
  persist()
}

function setRole(profileId, grant) {
  shares.value = shares.value.map((s) => (s.profileId === profileId ? { ...s, grant } : s))
  persist()
}

function revoke(profileId) {
  shares.value = shares.value.filter((s) => s.profileId !== profileId)
  persist()
}

watch(() => props.binder?.id, load, { immediate: true })

const SELECT =
  'rounded-lg bg-black/5 dark:bg-white/8 border border-transparent px-2.5 py-1.5 text-sm cursor-pointer focus:outline-none focus:border-indigo-500/50 disabled:cursor-default disabled:opacity-60'
</script>

<template>
  <div class="flex flex-col gap-4">
    <div v-if="loading" class="py-10 grid place-items-center text-slate-400">
      <Spinner class="w-5 h-5 animate-spin" />
    </div>

    <template v-else-if="data">
      <!-- A group binder isn't shared person by person: membership IS the grant,
           and only a Nucleus admin controls it. Say so plainly. -->
      <div
        v-if="data.group"
        class="rounded-xl border border-indigo-400/30 bg-indigo-500/10 p-3 flex items-start gap-2.5 text-sm"
      >
        <Icon name="users" :sw="2" class="w-4 h-4 shrink-0 mt-0.5 text-indigo-600 dark:text-indigo-400" />
        <p class="text-slate-700 dark:text-slate-200">
          Group binder for <strong>{{ data.group.name }}</strong> — all
          {{ data.group.memberCount }} members can add and remove cards.
          <span class="block text-xs text-slate-500 dark:text-slate-400 mt-0.5">
            Managed by a Nucleus administrator in the group's settings.
          </span>
        </p>
      </div>

      <!-- Owner -->
      <div v-if="data.owner" class="flex items-center gap-3">
        <AvatarCircle :profile="{ _id: data.owner.profileId, ...data.owner }" :size="32" />
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium truncate">{{ data.owner.name }}</p>
          <p class="text-xs text-slate-500 dark:text-slate-400">Owner</p>
        </div>
      </div>

      <!-- Grants -->
      <div v-if="shares.length" class="flex flex-col gap-2">
        <div v-for="s in shares" :key="s.profileId" class="flex items-center gap-3">
          <AvatarCircle :profile="{ _id: s.profileId, ...s }" :size="32" />
          <p class="min-w-0 flex-1 text-sm font-medium truncate">{{ s.name }}</p>
          <select
            :value="s.grant"
            :class="SELECT"
            :disabled="!canManage || saving"
            @change="setRole(s.profileId, $event.target.value)"
          >
            <option v-for="r in ROLES" :key="r.key" :value="r.key">{{ r.label }}</option>
          </select>
          <button
            v-if="canManage"
            class="cursor-pointer p-1.5 rounded-lg text-slate-400 hover:text-red-600 dark:hover:text-red-400 hover:bg-red-500/10 transition-colors disabled:opacity-50"
            :disabled="saving"
            title="Remove access"
            @click="revoke(s.profileId)"
          >
            <Icon name="close" :sw="2.5" class="w-4 h-4" />
          </button>
        </div>
      </div>

      <p v-else-if="!data.group" class="text-sm text-slate-500 dark:text-slate-400">
        This binder is private. Share it with someone to let them add and remove cards.
      </p>

      <!-- Add -->
      <template v-if="canManage">
        <button
          v-if="!adding"
          class="cursor-pointer self-start inline-flex items-center gap-2 rounded-lg bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 px-3 py-2 text-sm font-medium transition-colors"
          @click="adding = true"
        >
          <Icon name="plus" :sw="2.5" class="w-4 h-4" />
          Share with someone
        </button>

        <div v-else class="flex flex-col gap-2">
          <div class="relative">
            <Icon name="search" :sw="2" class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
            <input
              v-model="search"
              type="search"
              placeholder="Search people…"
              class="w-full rounded-lg bg-black/5 dark:bg-white/8 border border-transparent pl-9 pr-3 py-2 text-sm focus:outline-none focus:border-indigo-500/50"
            />
          </div>
          <div v-if="!candidates.length" class="text-sm text-slate-400 py-2">No one else to add.</div>
          <div v-else class="flex flex-col gap-1 max-h-48 overflow-y-auto">
            <button
              v-for="c in candidates"
              :key="c.profileId"
              class="cursor-pointer flex items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-black/5 dark:hover:bg-white/8 transition-colors text-left"
              @click="addPerson(c)"
            >
              <AvatarCircle :profile="{ _id: c.profileId, ...c }" :size="28" />
              <span class="text-sm truncate">{{ c.name }}</span>
            </button>
          </div>
          <button class="cursor-pointer self-start text-xs text-slate-500 hover:text-slate-900 dark:hover:text-white" @click="adding = false; search = ''">
            Cancel
          </button>
        </div>

        <!-- What the roles actually mean, stated once. -->
        <dl class="mt-1 grid gap-1 text-xs text-slate-500 dark:text-slate-400">
          <div v-for="r in ROLES" :key="r.key" class="flex gap-2">
            <dt class="font-medium text-slate-600 dark:text-slate-300 w-20 shrink-0">{{ r.label }}</dt>
            <dd>{{ r.hint }}</dd>
          </div>
        </dl>
      </template>

      <p v-if="error" class="text-xs text-red-500">{{ error }}</p>
    </template>

    <p v-else-if="error" class="text-xs text-red-500">{{ error }}</p>
  </div>
</template>
