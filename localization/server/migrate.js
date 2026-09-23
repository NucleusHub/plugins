import LocaleConfig from './LocaleConfig.js'

// Run by the auth-server on boot (see core/auth-server/serverPlugins.js).
// Ensures the singleton localization config exists.
export default async function migrate() {
  if (await LocaleConfig.findOne()) return
  await LocaleConfig.create({
    installedLanguages: ['en-US'],
    defaultLanguage: 'en-US',
    enabled: { core: ['en-US'] },
  })
  console.log('[localization] LocaleConfig created')
}
