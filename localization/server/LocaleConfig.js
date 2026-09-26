import mongoose from 'mongoose'

const localeConfigSchema = new mongoose.Schema({
  installedLanguages: { type: [String], default: ['en-US'] },
  defaultLanguage:    { type: String, default: 'en-US' },
  enabled:            { type: Map, of: [String], default: () => ({ core: ['en-US'] }) },
}, { timestamps: true })

export default mongoose.models.LocaleConfig || mongoose.model('LocaleConfig', localeConfigSchema)
