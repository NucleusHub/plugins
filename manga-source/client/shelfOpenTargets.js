// Open-in medium contributed to Shelf by the manga-source plugin.
//
// Books imported from this plugin's source carry an AniList id (see
// server/MangaProvider.js), so they open on manga sites instead of book stores.
// This is entirely self-contained: the medium id, label, the rule for which
// library entries it applies to, the destination list and their URL builders
// all live here — Shelf has no manga-specific code, it just merges whatever
// mediums its plugins contribute (see apps/shelf/client/src/utils/openTarget.js).
//
// Contract (Shelf's open-in extension point) — the default export is one medium
// descriptor, or an array of them:
//   {
//     id: string                      // medium id, unique across mediums
//     label: string                   // section label in Settings (literal)
//     match(entry): boolean           // does this medium apply to the entry?
//     defaultType: string             // default destination when unset
//     destinations: [
//       { type, label, build(ctx) }   // ctx = { entry, title, author, query, enc }
//     ]
//   }

const anilistUrl = (entry) => entry?.book?.identifiers?.anilistUrl ?? entry?.identifiers?.anilistUrl

export default {
  id: 'manga',
  label: 'Manga',
  match: (entry) => !!(entry?.book?.identifiers?.anilist ?? entry?.identifiers?.anilist),
  defaultType: 'anilist',
  destinations: [
    {
      type: 'anilist',
      label: 'AniList',
      // Deep-link to the exact AniList entry when we imported one; else search.
      build: ({ entry, title, enc }) => anilistUrl(entry) || `https://anilist.co/search/manga?search=${enc(title)}`,
    },
    { type: 'mangadex', label: 'MangaDex', build: ({ title, enc }) => `https://mangadex.org/search?q=${enc(title)}` },
    { type: 'mangaupdates', label: 'MangaUpdates', build: ({ title, enc }) => `https://www.mangaupdates.com/search.html?search=${enc(title)}` },
    { type: 'myanimelist', label: 'MyAnimeList', build: ({ title, enc }) => `https://myanimelist.net/manga.php?q=${enc(title)}` },
  ],
}
