import mongoose from 'mongoose'

const localeOverrideSchema = new mongoose.Schema({
  lang:  { type: String, required: true },
  key:   { type: String, required: true },
  value: { type: String, required: true },
}, { timestamps: true })

localeOverrideSchema.index({ lang: 1, key: 1 }, { unique: true })

export default mongoose.models.LocaleOverride || mongoose.model('LocaleOverride', localeOverrideSchema)
