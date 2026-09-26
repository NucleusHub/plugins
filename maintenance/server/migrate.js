import MaintenancePreset from './MaintenancePreset.js'

const BUILTIN_PRESETS = [
  {
    key: 'update', order: 1,
    title: { 'en-US': 'Nucleus is being updated', 'cs-CZ': 'Probíhá aktualizace Nucleus' },
    message: {
      'en-US': 'Nucleus is being updated to a new version — expect brief unresponsiveness for {eta}. File uploads and any changes may not be saved right now.',
      'cs-CZ': 'Nucleus se aktualizuje na novou verzi — počítejte s krátkou nedostupností po dobu {eta}. Nahrávání souborů a jakékoli změny se nyní nemusí uložit.',
    },
  },
  {
    key: 'rebuild', order: 2,
    title: { 'en-US': 'Nucleus is being rebuilt', 'cs-CZ': 'Přestavba Nucleus' },
    message: {
      'en-US': 'Containers are being rebuilt — Nucleus will be unavailable for {eta}. Please hold off on uploads or saving changes until this clears.',
      'cs-CZ': 'Kontejnery se přestavují — Nucleus bude nedostupný po dobu {eta}. Zdržte se prosím nahrávání nebo ukládání změn, dokud to neskončí.',
    },
  },
  {
    key: 'db', order: 3,
    title: { 'en-US': 'Database maintenance', 'cs-CZ': 'Údržba databáze' },
    message: {
      'en-US': 'Database maintenance in progress ({eta}). Any changes you make may not be saved until this finishes.',
      'cs-CZ': 'Probíhá údržba databáze ({eta}). Jakékoli změny se nemusí uložit, dokud údržba neskončí.',
    },
  },
  {
    key: 'quick', order: 4,
    title: { 'en-US': 'Quick restart', 'cs-CZ': 'Rychlý restart' },
    message: {
      'en-US': 'Quick restart in progress — back in {eta}.',
      'cs-CZ': 'Probíhá rychlý restart — vrátíme se za {eta}.',
    },
  },
]

export default async function migrate() {
  for (const p of BUILTIN_PRESETS) {
    const exists = await MaintenancePreset.findOne({ key: p.key })
    if (!exists) {
      await MaintenancePreset.create({ ...p, builtin: true, level: 'warning' })
      console.log(`[maintenance] preset '${p.key}' seeded`)
    }
  }
}
