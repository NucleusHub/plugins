import mongoose from 'mongoose'

// A single admin translation override. Overrides win over the shipped locale
// files and survive app/image updates (they live in Mongo, not on disk). One
// document per (lang, key); upserted/removed by the admin overrides endpoints.
// `key` is fully namespaced (e.g. 'core.button.save', 'photos.upload').
const localeOverrideSchema = new mongoose.Schema({
  lang:  { type: String, required: true },
  key:   { type: String, required: true },
  value: { type: String, required: true },
}, { timestamps: true })

localeOverrideSchema.index({ lang: 1, key: 1 }, { unique: true })

export default mongoose.models.LocaleOverride || mongoose.model('LocaleOverride', localeOverrideSchema)
