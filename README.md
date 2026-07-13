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
> metadata (`/api/plugins`). Beyond discovery, two extension surfaces are live:
> a plugin's `extensions.adminTabs` are mounted into the Admin Console, and a
> plugin's `server/route.js` is imported by the host it targets (e.g. the
> auth-server for `core` plugins). Plugins can be **enabled/disabled** globally
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

The current plugin API version is defined in
`infra/plugin-runtime/constants.js`. See `infra/nucleus-docs/PLUGINS.md` for the
full architecture.

## Optional plugins that gate host behavior

A core plugin can own a whole platform capability and cleanly degrade when it's
removed. **`localization`** is the reference example:

- Its `server/route.js` (mounted by the auth-server at `/api/auth/i18n` via a
  **guarded dynamic import**) owns multi-language catalogs, the per-app enable
  matrix, translation overrides, and the `LocaleConfig`/`LocaleOverride` models.
  Its `client/admin/LocalizationView.vue` is the Admin tab.
- When the plugin is **absent** the auth-server never mounts `/i18n`, and when
  it's **disabled** the client ignores it. Either way every app falls back to a
  **static single-language** mode: it renders its manifest default locale
  (`nucleus.app.json` → `localization.defaultLanguage`, default `en-US`) from a
  locale file bundled at build time. See `core/useI18n.js`.
- Sibling plugins that consumed `LocaleConfig` (maintenance, whats-new) read it
  defensively via `mongoose.models.LocaleConfig`, so they keep working
  (English-only) when localization isn't installed.
