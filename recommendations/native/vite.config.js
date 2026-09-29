import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'

// A native bundle is imported from a blob with nothing to resolve imports
// against, so Vue comes from the app instead (window.__nucleusVue).
function vueFromHost() {
  return {
    name: 'vue-from-host',
    renderChunk(code) {
      // The marketplace also wants a literal `export default`.
      code = code.replace(/export\s*\{\s*([\w$]+)\s+as\s+default\s*\};?/, 'export default $1;')
      return code.replace(/import\s*\{([^}]*)\}\s*from\s*["']vue["'];?/g, (_, names) => {
        const bindings = names.split(',').map((n) => n.trim()).filter(Boolean).map((n) => n.replace(/\s+as\s+/, ': '))
        return `const { ${bindings.join(', ')} } = globalThis.__nucleusVue;`
      })
    },
  }
}

export default defineConfig({
  root: fileURLToPath(new URL('.', import.meta.url)),
  envDir: false,
  define: { 'import.meta.env.VITE_TMDB_API_KEY': '""' },
  plugins: [vue(), tailwindcss(), vueFromHost()],
  resolve: {
    alias: { '@core/icons': fileURLToPath(new URL('./icons.js', import.meta.url)) },
  },
  build: {
    outDir: fileURLToPath(new URL('../client/native', import.meta.url)),
    emptyOutDir: true,
    minify: true,
    lib: {
      entry: fileURLToPath(new URL('./entry.js', import.meta.url)),
      formats: ['es'],
      fileName: () => 'watchlistSurface.js',
    },
    rollupOptions: { external: ['vue'] },
  },
})
