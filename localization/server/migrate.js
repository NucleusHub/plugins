import LocaleConfig from './LocaleConfig.js'

export default async function migrate() {
  if (await LocaleConfig.findOne()) return
  await LocaleConfig.create({
    installedLanguages: ['en-US'],
    defaultLanguage: 'en-US',
    enabled: { core: ['en-US'] },
  })
  console.log('[localization] LocaleConfig created')
}
