import mongoose from 'mongoose'

// A "What's New" release note, authored per language from the Admin Console
// (What's New tab). Announcements accumulate into a cumulative changelog: the
// login modal aggregates every published announcement into per-app tabs, grouped
// by version (newest first). See core/auth-server/routes/whatsNew.js,
// core/WhatsNewModal.vue and the per-user seen-state on Profile.whatsNew.
//
//  version      the Nucleus platform version for this release (e.g. '0.4.0'),
//               shown on top. Pre-filled from /api/registry/nucleus when authoring.
//  published    drafts are hidden from users; only published notes reach the feed.
//  publishedAt  stamped once on first publish. The modal auto-opens when this is
//               newer than the viewer's profile.whatsNew.lastSeenAt, so editing an
//               already-published note never re-pops it for everyone.
//  entries      per-app feature groups (become the modal's tabs). `app` is a
//               registry app id, or 'platform' for general/highlights.
//    version    the app's own version at this release (e.g. orbit '0.2.1'),
//               pre-filled from the registry manifest. Shown as the tab's header.
//    features   each: title (lang → heading), body (lang → text), optional icon.
const featureSchema = new mongoose.Schema({
  title: { type: Map, of: String, default: () => ({}) },
  body:  { type: Map, of: String, default: () => ({}) },
  icon:  { type: String, default: null },
}, { _id: false })

const entrySchema = new mongoose.Schema({
  app:      { type: String, required: true },
  version:  { type: String, default: '' },
  features: { type: [featureSchema], default: [] },
}, { _id: false })

const announcementSchema = new mongoose.Schema({
  version:     { type: String, required: true },
  published:   { type: Boolean, default: false },
  publishedAt: { type: Date, default: null },
  entries:     { type: [entrySchema], default: [] },
}, { timestamps: true })

export default mongoose.model('WhatsNewAnnouncement', announcementSchema)
