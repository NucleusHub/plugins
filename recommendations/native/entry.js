import css from './styles.css?inline'
import manifest from '../nucleus.plugin.json'
import component from '../client/watchlistSurface.vue'
import { connect } from '../client/host.js'

// The iOS app's watchlistSurface contract: the manifest's declaration plus the
// component, and connect() for the app to hand over its data layer.
// Reused on update, so a new version replaces the old styles.
const STYLE_ID = `nucleus-plugin-${manifest.id}`
let style = document.getElementById(STYLE_ID)
if (!style) {
  style = document.createElement('style')
  style.id = STYLE_ID
  document.head.appendChild(style)
}
style.textContent = css

const { bundle: _, ...decl } = manifest.extensions.watchlistSurface

export default { ...decl, component, connect }
