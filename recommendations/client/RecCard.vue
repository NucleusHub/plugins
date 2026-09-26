<script setup>
const props = defineProps({
  title: { type: String, required: true },
  year: { type: [Number, String], default: null },
  poster: { type: String, default: null },
  rating: { type: Number, default: null },
  genres: { type: Array, default: () => [] },
  why: { type: Object, default: null },
  actionLabel: { type: String, required: true },
  busy: { type: Boolean, default: false },
  danger: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
})
defineEmits(['action'])

const whyText = () => {
  if (!props.why) return null
  if (props.why.because?.length) return `Because you watched ${props.why.because.join(' and ')}`
  if (props.why.genres?.length) return `Matches your ${props.why.genres.join(' + ')} streak`
  return null
}
</script>

<template>
  <article
    :class="[
      'group flex flex-col rounded-xl overflow-hidden bg-white/70 dark:bg-slate-800/70 border border-white/60 dark:border-white/8 shadow-sm transition-all duration-200 ease-out hover:-translate-y-0.5 hover:shadow-md',
      compact ? 'w-36 shrink-0' : '',
    ]"
  >
    <div class="relative aspect-[2/3] bg-slate-100 dark:bg-slate-700/60">
      <img v-if="poster" :src="poster" :alt="title" loading="lazy" class="w-full h-full object-cover" />
      <div v-else class="w-full h-full flex items-center justify-center text-slate-300 dark:text-slate-600">
        <svg class="w-8 h-8" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5v10.5H3.75zM3.75 10.5h16.5M8.25 6.75v10.5" />
        </svg>
      </div>
      <span
        v-if="rating"
        class="absolute top-1.5 right-1.5 inline-flex items-center gap-0.5 rounded-full bg-black/65 px-1.5 py-0.5 text-[11px] font-medium text-amber-300 backdrop-blur-sm"
      >
        <svg class="w-2.5 h-2.5 fill-current" viewBox="0 0 24 24"><path d="M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9 6.8 19.6l1-5.8-4.3-4.1 5.9-.9z" /></svg>
        {{ rating }}
      </span>
    </div>

    <div class="flex flex-1 flex-col gap-1.5 p-2.5">
      <div class="min-w-0">
        <h4 class="truncate text-sm font-medium text-slate-900 dark:text-white" :title="title">{{ title }}</h4>
        <p v-if="year" class="text-xs text-slate-400 dark:text-slate-500">{{ year }}</p>
      </div>

      <p v-if="whyText()" class="text-[11px] leading-snug text-indigo-600/90 dark:text-indigo-400/90 line-clamp-2">
        {{ whyText() }}
      </p>

      <p v-if="genres.length && !compact" class="text-[11px] text-slate-400 dark:text-slate-500 truncate">
        {{ genres.slice(0, 3).join(' · ') }}
      </p>

      <button
        @click="$emit('action')"
        :disabled="busy"
        :class="[
          'nuc-press mt-auto cursor-pointer w-full rounded-lg px-2 py-1.5 text-xs font-medium text-white transition-colors disabled:cursor-wait disabled:opacity-60',
          danger ? 'bg-red-600/90 hover:bg-red-500' : 'bg-indigo-600 hover:bg-indigo-500',
        ]"
      >
        {{ busy ? 'Working…' : actionLabel }}
      </button>
    </div>
  </article>
</template>
