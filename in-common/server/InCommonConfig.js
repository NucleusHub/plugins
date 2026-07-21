import mongoose from 'mongoose'

// Instance-wide singleton config for the In Common plugin. Modelled on
// LocaleConfig — one document, read/written with findOne()/upsert, created
// lazily on first admin save.
//
// `scope` decides who the "also has this" lookup considers:
//   • 'network' — every (non-guest) profile on the install
//   • 'group'   — only members of the group(s) the viewer belongs to
//
// It defaults to 'network' on purpose: the only way to switch it to 'group' is
// the admin tab, so when the Admin app isn't installed the setting can never be
// changed and the feature safely stays network-wide — the documented behaviour.
//
// Registration is guarded (mongoose.models.X || model(...)) so co-loading in the
// same process (e.g. tests) never double-registers.
const schema = new mongoose.Schema(
  {
    scope: { type: String, enum: ['group', 'network'], default: 'network' },
  },
  { timestamps: true },
)

export default mongoose.models.InCommonConfig || mongoose.model('InCommonConfig', schema)
