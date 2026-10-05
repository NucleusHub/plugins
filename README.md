# Nucleus plugins

This directory holds installed **plugins**. A plugin is a package that extends
Core, a single app, or several apps at once. Each plugin lives in its own
directory named after its id:

```
/plugins
  /my-plugin
    nucleus.plugin.json   ← required manifest
    icon.svg              ← optional, inlined into the registry for the Admin UI
    …                     ← plugin code / assets (unused for now)
```

> **Status.** The `plugin-runtime` service *discovers* plugins and serves their
> metadata (`/api/plugins`). Beyond discovery, several extension surfaces are
> live: a plugin's `extensions.adminTabs` are mounted into the Admin Console, a
> plugin's `server/route.js` is mounted by the host it targets (the auth-server
> for `core` plugins — see *Server extension point*), and host apps glob fixed client filenames out
> of plugin dirs (see *App-level client extension points* below). Plugins can be **enabled/disabled** globally
> from Admin → **Plugins** (stored as `/api/auth/overrides` `plugins[]`); UI a
> plugin owns gates on that state. Dependency resolution and install/update flows
> are still future work.

## Discovery

The `plugin-runtime` service (`infra/plugin-runtime`) scans this directory, reads
each `nucleus.plugin.json`, validates it, and serves the results at
`/api/plugins`. A directory is only treated as a plugin if it contains a
manifest. Add a `nucleus.ignore` marker file to a directory to hide it from
discovery (same convention as apps/widgets).

## Manifest — `nucleus.plugin.json`

```jsonc
{
  "id": "my-plugin",              // required, kebab-case slug
  "name": "My Plugin",            // required
  "description": "What it does",  // optional

  "version": "1.0.0",             // required, SemVer
  "apiVersion": "0.1.0",          // required, which plugin API this targets

  "target": "core",               // required: "core", an app id, or an array of them
  "crossApp": false,              // required: true when target spans >1 app

  "author": "You",                // optional

  "dependencies": {               // optional
    "apps": { "orbit": ">=0.1.0" },
    "plugins": { "other-plugin": "^1.0.0" }
  },

  "permissions": ["files:read"],  // optional

  "extensions": {                 // optional — what the plugin contributes
    "authRoute": "/my-path",      // optional — see "Server extension point"
    "adminTabs": [
      { "path": "my-plugin", "label": "My Plugin", "component": "client/admin/MyView.vue" }
    ]
  }
}
```

Field notes:

- **`target`** — the surface the plugin extends. Use the reserved keyword
  `"core"` for a Core plugin, an app id (e.g. `"orbit"`) for an app plugin, or an
  array for a cross-app plugin.
- **`crossApp`** — must be `true` when `target` lists more than one app.
- **`apiVersion`** — compared against the runtime's `PLUGIN_API_VERSION` by SemVer
  major; a mismatch marks the plugin `incompatible` (still listed, not run).
- **`dependencies`** — declared only. Nucleus does **not** resolve them yet.
- **`extensions.adminTabs`** — admin tabs the plugin ships. Admin globs
  `plugins/*/client/admin/**/*.vue`, mounts the named component at `/{path}`, and
  hides the tab when the plugin is disabled. `component` is relative to the
  plugin dir.

## Core client extension point — `client/core.js`

A plugin targeting `core` can add chrome that every app renders by shipping
`client/core.js` (globbed by `core/usePluginExtensions.js`):

```js
export default {
  // Mounted once by core/auth/AuthGuard.vue in every app.
  // auth: true → signed-in viewers only; false → every auth state.
  mounts: [{ component: () => import('./Banner.vue'), auth: false }],
  // Buttons in the sidebar + profile switcher (signed-in viewers).
  launchers: [{ labelKey: 'core.foo.launch', icon, iconOutline, open }],
  // Rows in Profile settings → Plugins → Preferences. Receives the edited
  // `profile`; may emit `updated` after saving.
  preferences: [{ component: () => import('./Pref.vue') }],
}
```

Every entry is gated on the plugin being enabled. Core never imports a plugin
directly, so the platform builds and runs with `/plugins` empty or missing.
`maintenance` (banner) and `whats-new` (modal + launcher + preference) are the
reference examples.

## Server extension point — the auth-server

The auth-server (`core/auth-server/serverPlugins.js`) hosts a plugin when its
manifest targets `core` or sets `extensions.authRoute`. A hosted plugin may ship:

| File | What happens |
|---|---|
| `server/route.js` | Default-exported express `Router`, mounted at `/api/auth` + `extensions.authRoute` — `/api/auth/<id>` when omitted. `"authRoute": false` opts out. |
| `server/migrate.js` | Default-exported `async () => {}`, run on every boot after the DB connects. Keep it idempotent (seed only what's missing). |

A non-core plugin opts in with `authRoute` — `in-common` does, since its
cross-app lookup needs the identity data the auth-server owns. Nothing is named
in core: dropping a plugin in is enough, a missing `/plugins` hosts nothing,
and a plugin that fails to load is logged and skipped rather than taking the
server down.

## App-level client extension points

Beyond admin tabs, a host app can invite plugins into its own UI. Each point is
a **fixed filename** the app globs out of `plugins/*/client/` — globbing one
known name rather than a manifest-supplied path is what keeps unrelated plugin
code out of the app's bundle. Every one of them is gated on the plugin being
enabled, and a plugin only participates if its manifest `target` includes that
app.

| File a plugin ships | Host | What it contributes |
|---|---|---|
| `client/watchlistSources.js` | Watchlist | Extra metadata backends for the add/edit search box (see `apps/watchlist/client/src/api/sources.js` for the contract). Also declared as `extensions.watchlistSources`. |
| `client/watchlistIndicator.vue` | Watchlist | A small badge on every item card. Receives `item`. |
| `client/watchlistSurface.vue` | Watchlist | A whole section of the app — see below. |
| `client/shelfIndicator.vue`, `client/dexIndicator.vue` | Shelf, Dex | The same badge idea in the sibling apps. |

### `watchlistSurface` — a plugin-owned section of the Watchlist

The plugin ships `client/watchlistSurface.vue` and describes it in the manifest:

```jsonc
"extensions": {
  "watchlistSurface": {
    "path": "for-you",              // route segment, mounted at /watchlist/x/{path}
    "label": "For You",             // nav tab label (an i18n key also works)
    "placements": ["tab", "panel"], // which the component can handle; default both
    "defaultPlacement": "tab"       // until the user chooses
  }
}
```

**The user picks where it renders**, in Watchlist → Settings → Extras: its own
nav tab, a panel above the item grid, or off. The choice is stored per profile
(`WatchlistSettings.pluginPlacements`), so it follows them across devices and
survives the plugin being reinstalled.

The component is the same in both placements — the host tells it which it's in
and hands it the data:

| | |
|---|---|
| prop `items` | the viewer's full watchlist, already loaded by the host |
| prop `placement` | `'tab'` or `'panel'`, so it can render compactly in a panel |
| emit `changed` | asks the host to reload items (the plugin added or changed one) |

In tab placement the host wraps it in `views/PluginSurfaceView.vue`, which owns
the header, sidebar and nav — a surface never renders app chrome itself.

`recommendations` is the reference example.

**iOS app.** The Watchlist iOS app can't glob `plugins/`; it installs a surface
from the marketplace as one self-contained module, named by the declaration's
`"bundle"` key. Its default export is the declaration plus `component` and
`connect(host)` (the app passes `createItem`, `updateItem`, `tmdbKey`), and it
reads Vue from `globalThis.__nucleusVue`. `recommendations` builds its bundle
with `npm run build:native`; commit the output, since the marketplace reads it
straight from the checkout.

### Native (Swift) plugins

A plugin can also ship a Swift build, for native apps. `anime-source` is the reference example:

| File | What it is |
|---|---|
| `Package.swift` | A SwiftPM package whose one target reads `nucleus.plugin.json` as a resource, so Node and Swift share the manifest. |
| `native/Sources/…` | A type conforming to `Plugin` (from `nucleus-native-plugins`) that contributes to the host's extension points. |

The host app adds the package (a local `path:` in `project.yml`) and installs the plugin at launch with
`PluginRegistry.install(_:)`. Each host defines its own contract package for its extension points — Watchlist's is
`apps/watchlist/plugin-kit` (`SearchSource`) — which the plugin depends on. iOS can't load downloaded code, so native
plugins are compiled in; the registry still checks `target` and `apiVersion`, and gives the person an on/off switch.
See `nucleus-native-plugins/README.md`.

The current plugin API version is defined in
`infra/plugin-runtime/constants.js`. See `infra/nucleus-docs/PLUGINS.md` for the
full architecture.

## Optional plugins that gate host behavior

A core plugin can own a whole platform capability and cleanly degrade when it's
removed. **`localization`** is the reference example:

- Its `server/route.js` (mounted by the auth-server at `/api/auth/i18n` via
  `"authRoute": "/i18n"`) owns multi-language catalogs, the per-app enable
  matrix, translation overrides, and the `LocaleConfig`/`LocaleOverride` models;
  its `server/migrate.js` seeds the singleton `LocaleConfig`.
  Its `client/admin/LocalizationView.vue` is the Admin tab.
- When the plugin is **absent** the auth-server never mounts `/i18n`, and when
  it's **disabled** the client ignores it. Either way every app falls back to a
  **static single-language** mode: it renders its manifest default locale
  (`nucleus.app.json` → `localization.defaultLanguage`, default `en-US`) from a
  locale file bundled at build time. See `core/useI18n.js`.
- Sibling plugins that consumed `LocaleConfig` (maintenance, whats-new) read it
  defensively via `mongoose.models.LocaleConfig`, so they keep working
  (English-only) when localization isn't installed.
