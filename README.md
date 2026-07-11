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

> **Status: infrastructure only.** Nucleus can currently *discover* plugins and
> read their metadata. It does **not** execute plugin code, resolve dependencies,
> or enable/disable anything yet. Those land in later PRs. A plugin dropped here
> today shows up on the Admin → **Plugins** page and nothing more.

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

  "permissions": ["files:read"]   // optional
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

The current plugin API version is defined in
`infra/plugin-runtime/constants.js`. See `infra/nucleus-docs/PLUGINS.md` for the
full architecture.
