import { useWhatsNew } from './useWhatsNew.js'
import SparkleIcon from '@core/assets/icons/sparkle.svg?component'
import SparkleOutlineIcon from '@core/assets/icons/sparkle-outline.svg?component'

const { open } = useWhatsNew()

export default {
  mounts: [{ component: () => import('./WhatsNewModal.vue'), auth: true }],
  launchers: [{ labelKey: 'core.whatsNew.launch', icon: SparkleIcon, iconOutline: SparkleOutlineIcon, open }],
  preferences: [{ component: () => import('./ProfilePreference.vue') }],
}
