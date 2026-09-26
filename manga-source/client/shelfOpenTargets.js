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
      build: ({ entry, title, enc }) => anilistUrl(entry) || `https://anilist.co/search/manga?search=${enc(title)}`,
    },
    { type: 'mangadex', label: 'MangaDex', build: ({ title, enc }) => `https://mangadex.org/search?q=${enc(title)}` },
    { type: 'mangaupdates', label: 'MangaUpdates', build: ({ title, enc }) => `https://www.mangaupdates.com/search.html?search=${enc(title)}` },
    { type: 'myanimelist', label: 'MyAnimeList', build: ({ title, enc }) => `https://myanimelist.net/manga.php?q=${enc(title)}` },
  ],
}
