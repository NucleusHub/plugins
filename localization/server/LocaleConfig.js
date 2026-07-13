import mongoose from 'mongoose'

// Instance-wide localization state. A single document (singleton) — created by
// this plugin's route on first access (and seeded by the auth-server migration
// when the plugin is installed). See plugins/localization/server/route.js.
//
//  installedLanguages  languages activated in this Nucleus instance (BCP-47
//                      tags). Installing ≠ enabling; a language stays installed
//                      until an admin explicitly removes it. 'en-US' is the base
//                      and is always installed.
//  defaultLanguage     the fallback language used when a user has no assigned
//                      locale. Always 'en-US' unless an admin changes it.
//  enabled             per-scope map of enabled languages. Scope key is 'core'
//                      or an app id (e.g. 'orbit'). A language must be installed
//                      AND enabled for a scope to be offered there; runtime
//                      lookups always fall back to English regardless.
//
// This model is only registered when the localization plugin is installed;
// maintenance/whats-new read it defensively via mongoose.models.LocaleConfig so
// they keep working (English-only) when localization isn't installed.
const localeConfigSchema = new mongoose.Schema({
  installedLanguages: { type: [String], default: ['en-US'] },
  defaultLanguage:    { type: String, default: 'en-US' },
  enabled:            { type: Map, of: [String], default: () => ({ core: ['en-US'] }) },
}, { timestamps: true })

export default mongoose.models.LocaleConfig || mongoose.model('LocaleConfig', localeConfigSchema)
