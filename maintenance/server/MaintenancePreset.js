import mongoose from 'mongoose'

// A named maintenance-banner message, translated per language and managed from
// the Admin Console (Maintenance tab). When an admin raises the banner with a
// preset, the maintenance route renders each installed language's title/message
// into the static flag file (state/maintenance.json) so the banner is fully
// self-contained — it keeps showing, already translated, even while the app
// servers are being rebuilt. See core/auth-server/routes/maintenance.js.
//
//  key      stable slug (e.g. 'update'). Unique. Used by the CLI-parity presets.
//  builtin  seeded default (update/rebuild/db/quick). Editable but not deletable,
//           so the shipped set is always available.
//  order    display order in the admin list.
//  level    severity tag carried into the flag ('warning' today).
//  title    lang → banner heading.
//  message  lang → banner body. May contain an {eta} placeholder, filled with the
//           formatted ETA when the banner is raised.
const maintenancePresetSchema = new mongoose.Schema({
  key:     { type: String, required: true, unique: true },
  builtin: { type: Boolean, default: false },
  order:   { type: Number, default: 100 },
  level:   { type: String, default: 'warning' },
  title:   { type: Map, of: String, default: () => ({}) },
  message: { type: Map, of: String, default: () => ({}) },
}, { timestamps: true })

export default mongoose.model('MaintenancePreset', maintenancePresetSchema)
