// Core extension point (see core/usePluginExtensions.js): the platform-wide
// maintenance banner, shown in every app regardless of auth state.
export default {
  mounts: [{ component: () => import('./MaintenanceBanner.vue'), auth: false }],
}
