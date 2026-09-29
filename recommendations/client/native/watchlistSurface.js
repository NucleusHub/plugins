const { Fragment: e, computed: t, createBlock: n, createCommentVNode: r, createElementBlock: i, createElementVNode: a, createTextVNode: o, createVNode: s, h: c, normalizeClass: l, openBlock: u, ref: d, renderList: f, toDisplayString: p, unref: m, watch: h } = globalThis.__nucleusVue;
//#region native/styles.css?inline
var g = "/*! tailwindcss v4.3.3 | MIT License | https://tailwindcss.com */\n@layer properties{@supports (((-webkit-hyphens:none)) and (not (margin-trim:inline))) or ((-moz-orient:inline) and (not (color:rgb(from red r g b)))){*,:before,:after,::backdrop{--tw-border-style:solid;--tw-leading:initial;--tw-font-weight:initial;--tw-shadow:0 0 #0000;--tw-shadow-color:initial;--tw-shadow-alpha:100%;--tw-inset-shadow:0 0 #0000;--tw-inset-shadow-color:initial;--tw-inset-shadow-alpha:100%;--tw-ring-color:initial;--tw-ring-shadow:0 0 #0000;--tw-inset-ring-color:initial;--tw-inset-ring-shadow:0 0 #0000;--tw-ring-inset:initial;--tw-ring-offset-width:0px;--tw-ring-offset-color:#fff;--tw-ring-offset-shadow:0 0 #0000;--tw-backdrop-blur:initial;--tw-backdrop-brightness:initial;--tw-backdrop-contrast:initial;--tw-backdrop-grayscale:initial;--tw-backdrop-hue-rotate:initial;--tw-backdrop-invert:initial;--tw-backdrop-opacity:initial;--tw-backdrop-saturate:initial;--tw-backdrop-sepia:initial;--tw-duration:initial;--tw-ease:initial;--tw-translate-x:0;--tw-translate-y:0;--tw-translate-z:0}}}@layer theme{:root,:host{--color-red-500:oklch(63.7% .237 25.331);--color-red-600:oklch(57.7% .245 27.325);--color-amber-300:oklch(87.9% .169 91.605);--color-amber-400:oklch(82.8% .189 84.429);--color-amber-600:oklch(66.6% .179 58.318);--color-indigo-400:oklch(67.3% .182 276.935);--color-indigo-500:oklch(58.5% .233 277.117);--color-indigo-600:oklch(51.1% .262 276.966);--color-slate-100:oklch(96.8% .007 247.896);--color-slate-200:oklch(92.9% .013 255.508);--color-slate-300:oklch(86.9% .022 252.894);--color-slate-400:oklch(70.4% .04 256.788);--color-slate-500:oklch(55.4% .046 257.417);--color-slate-600:oklch(44.6% .043 257.281);--color-slate-700:oklch(37.2% .044 257.287);--color-slate-800:oklch(27.9% .041 260.031);--color-slate-900:oklch(20.8% .042 265.755);--color-black:#000;--color-white:#fff;--spacing:.25rem;--text-xs:.75rem;--text-xs--line-height:calc(1 / .75);--text-sm:.875rem;--text-sm--line-height:calc(1.25 / .875);--text-base:1rem;--text-base--line-height:calc(1.5 / 1);--font-weight-medium:500;--font-weight-semibold:600;--leading-snug:1.375;--radius-lg:.5rem;--radius-xl:.75rem;--radius-2xl:1rem;--ease-out:cubic-bezier(0, 0, .2, 1);--animate-spin:spin 1s linear infinite;--blur-sm:8px;--default-transition-duration:.15s;--default-transition-timing-function:cubic-bezier(.4, 0, .2, 1)}}@layer base,components;@layer utilities{.absolute{position:absolute}.relative{position:relative}.top-1{top:var(--spacing)}.top-1\\.5{top:calc(var(--spacing) * 1.5)}.right-1{right:var(--spacing)}.right-1\\.5{right:calc(var(--spacing) * 1.5)}.-mx-1{margin-inline:calc(var(--spacing) * -1)}.mt-0{margin-top:0}.mt-0\\.5{margin-top:calc(var(--spacing) * .5)}.mt-auto{margin-top:auto}.line-clamp-2{-webkit-line-clamp:2;-webkit-box-orient:vertical;display:-webkit-box;overflow:hidden}.flex{display:flex}.grid{display:grid}.hidden{display:none}.inline-flex{display:inline-flex}.aspect-\\[2\\/3\\]{aspect-ratio:2/3}.h-2{height:calc(var(--spacing) * 2)}.h-2\\.5{height:calc(var(--spacing) * 2.5)}.h-3{height:calc(var(--spacing) * 3)}.h-3\\.5{height:calc(var(--spacing) * 3.5)}.h-7{height:calc(var(--spacing) * 7)}.h-8{height:calc(var(--spacing) * 8)}.h-full{height:100%}.w-2{width:calc(var(--spacing) * 2)}.w-2\\.5{width:calc(var(--spacing) * 2.5)}.w-3{width:calc(var(--spacing) * 3)}.w-3\\.5{width:calc(var(--spacing) * 3.5)}.w-8{width:calc(var(--spacing) * 8)}.w-36{width:calc(var(--spacing) * 36)}.w-full{width:100%}.min-w-0{min-width:0}.flex-1{flex:1}.shrink-0{flex-shrink:0}.animate-spin{animation:var(--animate-spin)}.cursor-pointer{cursor:pointer}.grid-cols-2{grid-template-columns:repeat(2,minmax(0,1fr))}.flex-col{flex-direction:column}.items-baseline{align-items:baseline}.items-center{align-items:center}.justify-between{justify-content:space-between}.justify-center{justify-content:center}.gap-0{gap:0}.gap-0\\.5{gap:calc(var(--spacing) * .5)}.gap-1{gap:var(--spacing)}.gap-1\\.5{gap:calc(var(--spacing) * 1.5)}.gap-2{gap:calc(var(--spacing) * 2)}.gap-3{gap:calc(var(--spacing) * 3)}.gap-4{gap:calc(var(--spacing) * 4)}.self-start{align-self:flex-start}.truncate{text-overflow:ellipsis;white-space:nowrap;overflow:hidden}.overflow-hidden{overflow:hidden}.overflow-x-auto{overflow-x:auto}.rounded-2xl{border-radius:var(--radius-2xl)}.rounded-full{border-radius:2147483647px}.rounded-lg{border-radius:var(--radius-lg)}.rounded-xl{border-radius:var(--radius-xl)}.border{border-style:var(--tw-border-style);border-width:1px}.border-white{border-color:var(--color-white)}.border-white\\/60{border-color:#fff9}@supports (color:color-mix(in lab, red, red)){.border-white\\/60{border-color:color-mix(in oklab, var(--color-white) 60%, transparent)}}.bg-black{background-color:var(--color-black)}.bg-black\\/65{background-color:#000000a6}@supports (color:color-mix(in lab, red, red)){.bg-black\\/65{background-color:color-mix(in oklab, var(--color-black) 65%, transparent)}}.bg-black\\/\\[0\\.04\\]{background-color:#0000000a}@supports (color:color-mix(in lab, red, red)){.bg-black\\/\\[0\\.04\\]{background-color:color-mix(in oklab, var(--color-black) 4%, transparent)}}.bg-indigo-600{background-color:var(--color-indigo-600)}.bg-red-600{background-color:var(--color-red-600)}.bg-red-600\\/90{background-color:#e40014e6}@supports (color:color-mix(in lab, red, red)){.bg-red-600\\/90{background-color:color-mix(in oklab, var(--color-red-600) 90%, transparent)}}.bg-slate-100{background-color:var(--color-slate-100)}.bg-white{background-color:var(--color-white)}.bg-white\\/70{background-color:#ffffffb3}@supports (color:color-mix(in lab, red, red)){.bg-white\\/70{background-color:color-mix(in oklab, var(--color-white) 70%, transparent)}}.fill-current{fill:currentColor}.object-cover{object-fit:cover}.p-1{padding:var(--spacing)}.p-2{padding:calc(var(--spacing) * 2)}.p-2\\.5{padding:calc(var(--spacing) * 2.5)}.p-4{padding:calc(var(--spacing) * 4)}.px-1{padding-inline:var(--spacing)}.px-1\\.5{padding-inline:calc(var(--spacing) * 1.5)}.px-2{padding-inline:calc(var(--spacing) * 2)}.px-2\\.5{padding-inline:calc(var(--spacing) * 2.5)}.py-0{padding-block:0}.py-0\\.5{padding-block:calc(var(--spacing) * .5)}.py-1{padding-block:var(--spacing)}.py-1\\.5{padding-block:calc(var(--spacing) * 1.5)}.pb-1{padding-bottom:var(--spacing)}.text-base{font-size:var(--text-base);line-height:var(--tw-leading,var(--text-base--line-height))}.text-sm{font-size:var(--text-sm);line-height:var(--tw-leading,var(--text-sm--line-height))}.text-xs{font-size:var(--text-xs);line-height:var(--tw-leading,var(--text-xs--line-height))}.text-\\[11px\\]{font-size:11px}.leading-snug{--tw-leading:var(--leading-snug);line-height:var(--leading-snug)}.font-medium{--tw-font-weight:var(--font-weight-medium);font-weight:var(--font-weight-medium)}.font-semibold{--tw-font-weight:var(--font-weight-semibold);font-weight:var(--font-weight-semibold)}.whitespace-nowrap{white-space:nowrap}.text-amber-300{color:var(--color-amber-300)}.text-amber-600{color:var(--color-amber-600)}.text-indigo-600{color:var(--color-indigo-600)}.text-indigo-600\\/90{color:#4f39f6e6}@supports (color:color-mix(in lab, red, red)){.text-indigo-600\\/90{color:color-mix(in oklab, var(--color-indigo-600) 90%, transparent)}}.text-slate-300{color:var(--color-slate-300)}.text-slate-400{color:var(--color-slate-400)}.text-slate-500{color:var(--color-slate-500)}.text-slate-700{color:var(--color-slate-700)}.text-slate-900{color:var(--color-slate-900)}.text-white{color:var(--color-white)}.shadow-sm{--tw-shadow:0 1px 3px 0 var(--tw-shadow-color,#0000001a), 0 1px 2px -1px var(--tw-shadow-color,#0000001a);box-shadow:var(--tw-inset-shadow), var(--tw-inset-ring-shadow), var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow)}.backdrop-blur-sm{--tw-backdrop-blur:blur(var(--blur-sm));-webkit-backdrop-filter:var(--tw-backdrop-blur,) var(--tw-backdrop-brightness,) var(--tw-backdrop-contrast,) var(--tw-backdrop-grayscale,) var(--tw-backdrop-hue-rotate,) var(--tw-backdrop-invert,) var(--tw-backdrop-opacity,) var(--tw-backdrop-saturate,) var(--tw-backdrop-sepia,);backdrop-filter:var(--tw-backdrop-blur,) var(--tw-backdrop-brightness,) var(--tw-backdrop-contrast,) var(--tw-backdrop-grayscale,) var(--tw-backdrop-hue-rotate,) var(--tw-backdrop-invert,) var(--tw-backdrop-opacity,) var(--tw-backdrop-saturate,) var(--tw-backdrop-sepia,)}.transition-all{transition-property:all;transition-timing-function:var(--tw-ease,var(--default-transition-timing-function));transition-duration:var(--tw-duration,var(--default-transition-duration))}.transition-colors{transition-property:color,background-color,border-color,outline-color,text-decoration-color,fill,stroke,--tw-gradient-from,--tw-gradient-via,--tw-gradient-to;transition-timing-function:var(--tw-ease,var(--default-transition-timing-function));transition-duration:var(--tw-duration,var(--default-transition-duration))}.duration-200{--tw-duration:.2s;transition-duration:.2s}.ease-out{--tw-ease:var(--ease-out);transition-timing-function:var(--ease-out)}@media (hover:hover){.hover\\:-translate-y-0\\.5:hover{--tw-translate-y:calc(var(--spacing) * -.5);translate:var(--tw-translate-x) var(--tw-translate-y)}.hover\\:bg-black\\/5:hover{background-color:#0000000d}@supports (color:color-mix(in lab, red, red)){.hover\\:bg-black\\/5:hover{background-color:color-mix(in oklab, var(--color-black) 5%, transparent)}}.hover\\:bg-indigo-500:hover{background-color:var(--color-indigo-500)}.hover\\:bg-red-500:hover{background-color:var(--color-red-500)}.hover\\:text-slate-900:hover{color:var(--color-slate-900)}.hover\\:shadow-md:hover{--tw-shadow:0 4px 6px -1px var(--tw-shadow-color,#0000001a), 0 2px 4px -2px var(--tw-shadow-color,#0000001a);box-shadow:var(--tw-inset-shadow), var(--tw-inset-ring-shadow), var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow)}}.disabled\\:cursor-not-allowed:disabled{cursor:not-allowed}.disabled\\:cursor-wait:disabled{cursor:wait}.disabled\\:opacity-40:disabled{opacity:.4}.disabled\\:opacity-60:disabled{opacity:.6}@media (width>=40rem){.sm\\:block{display:block}.sm\\:grid-cols-3{grid-template-columns:repeat(3,minmax(0,1fr))}.sm\\:flex-row{flex-direction:row}.sm\\:items-start{align-items:flex-start}.sm\\:justify-between{justify-content:space-between}.sm\\:self-auto{align-self:auto}}@media (width>=64rem){.lg\\:grid-cols-4{grid-template-columns:repeat(4,minmax(0,1fr))}}.dark\\:border-white\\/8:where(.dark,.dark *){border-color:#ffffff14}@supports (color:color-mix(in lab, red, red)){.dark\\:border-white\\/8:where(.dark,.dark *){border-color:color-mix(in oklab, var(--color-white) 8%, transparent)}}.dark\\:bg-slate-700\\/60:where(.dark,.dark *){background-color:#31415899}@supports (color:color-mix(in lab, red, red)){.dark\\:bg-slate-700\\/60:where(.dark,.dark *){background-color:color-mix(in oklab, var(--color-slate-700) 60%, transparent)}}.dark\\:bg-slate-800\\/70:where(.dark,.dark *){background-color:#1d293db3}@supports (color:color-mix(in lab, red, red)){.dark\\:bg-slate-800\\/70:where(.dark,.dark *){background-color:color-mix(in oklab, var(--color-slate-800) 70%, transparent)}}.dark\\:bg-white\\/5:where(.dark,.dark *){background-color:#ffffff0d}@supports (color:color-mix(in lab, red, red)){.dark\\:bg-white\\/5:where(.dark,.dark *){background-color:color-mix(in oklab, var(--color-white) 5%, transparent)}}.dark\\:bg-white\\/15:where(.dark,.dark *){background-color:#ffffff26}@supports (color:color-mix(in lab, red, red)){.dark\\:bg-white\\/15:where(.dark,.dark *){background-color:color-mix(in oklab, var(--color-white) 15%, transparent)}}.dark\\:text-amber-400:where(.dark,.dark *){color:var(--color-amber-400)}.dark\\:text-indigo-400\\/90:where(.dark,.dark *){color:#7d87ffe6}@supports (color:color-mix(in lab, red, red)){.dark\\:text-indigo-400\\/90:where(.dark,.dark *){color:color-mix(in oklab, var(--color-indigo-400) 90%, transparent)}}.dark\\:text-slate-200:where(.dark,.dark *){color:var(--color-slate-200)}.dark\\:text-slate-400:where(.dark,.dark *){color:var(--color-slate-400)}.dark\\:text-slate-500:where(.dark,.dark *){color:var(--color-slate-500)}.dark\\:text-slate-600:where(.dark,.dark *){color:var(--color-slate-600)}.dark\\:text-white:where(.dark,.dark *){color:var(--color-white)}@media (hover:hover){.dark\\:hover\\:bg-white\\/8:where(.dark,.dark *):hover{background-color:#ffffff14}@supports (color:color-mix(in lab, red, red)){.dark\\:hover\\:bg-white\\/8:where(.dark,.dark *):hover{background-color:color-mix(in oklab, var(--color-white) 8%, transparent)}}.dark\\:hover\\:text-white:where(.dark,.dark *):hover{color:var(--color-white)}}}@property --tw-border-style{syntax:\"*\";inherits:false;initial-value:solid}@property --tw-leading{syntax:\"*\";inherits:false}@property --tw-font-weight{syntax:\"*\";inherits:false}@property --tw-shadow{syntax:\"*\";inherits:false;initial-value:0 0 #0000}@property --tw-shadow-color{syntax:\"*\";inherits:false}@property --tw-shadow-alpha{syntax:\"<percentage>\";inherits:false;initial-value:100%}@property --tw-inset-shadow{syntax:\"*\";inherits:false;initial-value:0 0 #0000}@property --tw-inset-shadow-color{syntax:\"*\";inherits:false}@property --tw-inset-shadow-alpha{syntax:\"<percentage>\";inherits:false;initial-value:100%}@property --tw-ring-color{syntax:\"*\";inherits:false}@property --tw-ring-shadow{syntax:\"*\";inherits:false;initial-value:0 0 #0000}@property --tw-inset-ring-color{syntax:\"*\";inherits:false}@property --tw-inset-ring-shadow{syntax:\"*\";inherits:false;initial-value:0 0 #0000}@property --tw-ring-inset{syntax:\"*\";inherits:false}@property --tw-ring-offset-width{syntax:\"<length>\";inherits:false;initial-value:0}@property --tw-ring-offset-color{syntax:\"*\";inherits:false;initial-value:#fff}@property --tw-ring-offset-shadow{syntax:\"*\";inherits:false;initial-value:0 0 #0000}@property --tw-backdrop-blur{syntax:\"*\";inherits:false}@property --tw-backdrop-brightness{syntax:\"*\";inherits:false}@property --tw-backdrop-contrast{syntax:\"*\";inherits:false}@property --tw-backdrop-grayscale{syntax:\"*\";inherits:false}@property --tw-backdrop-hue-rotate{syntax:\"*\";inherits:false}@property --tw-backdrop-invert{syntax:\"*\";inherits:false}@property --tw-backdrop-opacity{syntax:\"*\";inherits:false}@property --tw-backdrop-saturate{syntax:\"*\";inherits:false}@property --tw-backdrop-sepia{syntax:\"*\";inherits:false}@property --tw-duration{syntax:\"*\";inherits:false}@property --tw-ease{syntax:\"*\";inherits:false}@property --tw-translate-x{syntax:\"*\";inherits:false;initial-value:0}@property --tw-translate-y{syntax:\"*\";inherits:false;initial-value:0}@property --tw-translate-z{syntax:\"*\";inherits:false;initial-value:0}@keyframes spin{to{transform:rotate(360deg)}}", _ = {
	id: "recommendations",
	name: "For You",
	description: "Suggests what to watch next from what you've finished recently. Builds a taste profile out of your completed items' genres — weighted by how recently you watched them and how you rated them — then re-ranks your own backlog against it and pulls fresh titles from TMDb that you don't have yet. Choose whether it gets its own tab or sits as a panel above your list in Settings → Extras.",
	version: "1.0.0",
	apiVersion: "0.1.0",
	target: "watchlist",
	crossApp: !1,
	author: "Nucleus",
	dependencies: { apps: { watchlist: ">=0.7.0" } },
	extensions: { watchlistSurface: {
		path: "for-you",
		label: "For You",
		placements: ["tab", "panel"],
		defaultPlacement: "tab",
		bundle: "client/native/watchlistSurface.js"
	} }
}, v = 60, y = 864e5, b = 60, x = (e) => new Date(e.completedAt ?? e.updatedAt ?? e.dateAdded ?? 0);
function S(e) {
	let t = e.rating == null ? 1 : (e.rating - 5.5) / 2.5;
	return t = Math.max(-1.5, Math.min(2, t)), e.favorite && (t += .5), t;
}
function C(e, t) {
	return .5 ** (Math.max(0, (t - x(e)) / y) / v);
}
function ee(e, t = Date.now()) {
	return (e ?? []).filter((e) => e.status === "completed").sort((e, t) => x(t) - x(e)).slice(0, b).map((e) => {
		let n = C(e, t), r = S(e);
		return {
			item: e,
			recency: n,
			quality: r,
			weight: n * r
		};
	});
}
function te(e) {
	let t = /* @__PURE__ */ new Map();
	for (let n of e) {
		let e = n.item.genres ?? [];
		if (!e.length) continue;
		let r = n.weight / Math.sqrt(e.length);
		for (let n of e) {
			let e = n.toLowerCase(), i = t.get(e) ?? {
				name: n,
				score: 0
			};
			i.score += r, t.set(e, i);
		}
	}
	let n = 0;
	for (let { score: e } of t.values()) n = Math.max(n, Math.abs(e));
	if (!n) return /* @__PURE__ */ new Map();
	let r = /* @__PURE__ */ new Map();
	for (let [e, { name: i, score: a }] of t) r.set(e, {
		name: i,
		score: a / n
	});
	return r;
}
var w = .05;
function T(e, t = 5) {
	return [...e.values()].filter((e) => e.score > w).sort((e, t) => t.score - e.score).slice(0, t);
}
function E(e, t) {
	let n = e ?? [];
	if (!n.length || !t.size) return 0;
	let r = 0;
	for (let e of n) r += t.get(e.toLowerCase())?.score ?? 0;
	return r / Math.sqrt(n.length);
}
function D(e, t, n) {
	let r = (e ?? []).map((e) => t.get(e.toLowerCase())).filter((e) => e && e.score > .15).sort((e, t) => t.score - e.score).slice(0, 2);
	if (!r.length) return null;
	let i = new Set(r.map((e) => e.name.toLowerCase())), a = n.filter((e) => e.weight > 0 && (e.item.genres ?? []).some((e) => i.has(e.toLowerCase()))).slice(0, 2).map((e) => e.item.title);
	return {
		genres: r.map((e) => e.name),
		because: a
	};
}
function O(e) {
	let t = 0;
	return e.tmdbRating && (t += (e.tmdbRating - 6) * .06), e.favorite && (t += .4), e.watchLink && (t += .05), t;
}
function ne(e, { affinity: t, signals: n, type: r = "all", limit: i = 12 }) {
	return {
		hasProfile: t.size > 0,
		results: (e ?? []).filter((e) => e.status === "planned" && (r === "all" || e.type === r)).map((e) => {
			let r = E(e.genres, t);
			return {
				item: e,
				score: r + O(e),
				fit: r,
				why: D(e.genres, t, n)
			};
		}).sort((e, t) => t.score - e.score).slice(0, i)
	};
}
//#endregion
//#region client/host.js
async function k(e, t, n) {
	let r = await fetch(t, {
		method: e,
		headers: { "Content-Type": "application/json" },
		credentials: "same-origin",
		body: JSON.stringify(n)
	});
	if (!r.ok) throw Error(`${e} failed (${r.status})`);
	return r.json();
}
var A = {
	createItem: (e) => k("POST", "/api/watchlist", e),
	updateItem: (e, t) => k("PATCH", `/api/watchlist/${e}`, t),
	tmdbKey: () => ""
}, j = () => A;
function M(e = {}) {
	for (let t of Object.keys(A)) typeof e[t] == "function" && (A[t] = e[t]);
}
//#endregion
//#region client/tmdb.js
var N = "https://api.themoviedb.org/3", P = class extends Error {
	constructor() {
		super("No TMDb API key"), this.name = "NoKeyError";
	}
}, F = () => !!j().tmdbKey();
async function I(e, t = {}) {
	let n = j().tmdbKey();
	if (!n) throw new P();
	let r = new URL(`${N}${e}`);
	r.searchParams.set("api_key", n);
	for (let [e, n] of Object.entries(t)) n != null && n !== "" && r.searchParams.set(e, String(n));
	let i = await fetch(r);
	if (!i.ok) throw Error(`TMDb ${i.status}`);
	return i.json();
}
var L = "watchlist-recs:genres", R = 2592e6, z = null;
async function B() {
	let [e, t] = await Promise.all([I("/genre/movie/list"), I("/genre/tv/list")]);
	return {
		movie: Object.fromEntries((e.genres ?? []).map((e) => [e.id, e.name])),
		tv: Object.fromEntries((t.genres ?? []).map((e) => [e.id, e.name]))
	};
}
function V() {
	return z || (z = (async () => {
		try {
			let e = JSON.parse(localStorage.getItem(L) || "null");
			if (e?.at && Date.now() - e.at < R && e.maps?.movie) return e.maps;
		} catch {}
		let e = await B();
		try {
			localStorage.setItem(L, JSON.stringify({
				at: Date.now(),
				maps: e
			}));
		} catch {}
		return e;
	})(), z.catch(() => {
		z = null;
	}), z);
}
async function H(e) {
	let t = await V(), n = /* @__PURE__ */ new Map();
	for (let [r, i] of Object.entries(t[e] ?? {})) n.set(i.toLowerCase(), Number(r));
	return n;
}
function re(e, t) {
	return I(`/${t}/${e}/recommendations`).then((e) => e.results ?? []);
}
function U(e, t, { voteCountGte: n = 200, page: r = 1 } = {}) {
	return t.length ? I(`/discover/${e}`, {
		with_genres: t.join("|"),
		sort_by: "popularity.desc",
		"vote_count.gte": n,
		include_adult: !1,
		page: r
	}).then((e) => e.results ?? []) : Promise.resolve([]);
}
function ie(e, t) {
	return I(`/${t}/${e}`);
}
var W = (e, t = "w500") => e ? `https://image.tmdb.org/t/p/${t}${e}` : null, G = 4, K = 100, q = "watchlist-recs:discover:", J = 216e5, Y = 60, X = (e) => e.type === "movie" ? "movie" : "tv", ae = (e) => e === "movie" ? "movie" : "show", Z = (e, t) => `${String(e ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "")}:${t ?? ""}`;
function oe(e) {
	let t = /* @__PURE__ */ new Set(), n = /* @__PURE__ */ new Set();
	for (let r of e ?? []) r.tmdbId && t.add(`${X(r)}:${r.tmdbId}`), n.add(Z(r.title, r.year)), n.add(Z(r.title, ""));
	return {
		ids: t,
		titles: n
	};
}
var Q = (e, t) => e.ids.has(`${t.mediaType}:${t.tmdbId}`) || e.titles.has(Z(t.title, t.year ?? "")) || e.titles.has(Z(t.title, ""));
function se(e, t, n) {
	let r = (e.genre_ids ?? []).map((e) => n[t]?.[e]).filter(Boolean);
	return {
		key: `${t}:${e.id}`,
		tmdbId: e.id,
		mediaType: t,
		type: ae(t),
		title: e.title ?? e.name ?? "",
		year: Number((e.release_date ?? e.first_air_date)?.slice(0, 4)) || null,
		posterPath: e.poster_path ?? null,
		tmdbRating: e.vote_average ? Math.round(e.vote_average * 10) / 10 : null,
		voteCount: e.vote_count ?? 0,
		overview: e.overview ?? "",
		genres: r,
		score: 0,
		seeds: [],
		why: null
	};
}
function ce(e, t) {
	return `${q}${t}:${e.map((e) => `${X(e.item)}${e.item.tmdbId}`).sort().join(",")}`;
}
function le(e) {
	try {
		let t = JSON.parse(localStorage.getItem(e) || "null");
		if (t?.at && Date.now() - t.at < J) return t.results;
	} catch {}
	return null;
}
function ue(e, t) {
	try {
		localStorage.setItem(e, JSON.stringify({
			at: Date.now(),
			results: t
		}));
	} catch {}
}
function de() {
	try {
		let e = Object.keys(localStorage).filter((e) => e.startsWith(q));
		for (let t of e) localStorage.removeItem(t);
	} catch {}
}
async function fe(e, { affinity: t, signals: n, type: r = "all", limit: i = 12, offset: a = 0, force: o = !1 } = {}) {
	if (!F()) throw new P();
	let s = n.filter((e) => e.item.tmdbId && e.weight > 0).filter((e) => r === "all" || e.item.type === r).slice(0, G), c = s.map((e) => e.item.title), l = ce(s, r), u = (t, n) => {
		let r = oe(e), o = t.filter((e) => !Q(r, e)), s;
		if (o.length <= i) s = o;
		else {
			let e = a % o.length;
			s = Array.from({ length: i }, (t, n) => o[(e + n) % o.length]);
		}
		return {
			results: s,
			poolSize: o.length,
			seeds: c,
			cached: n
		};
	};
	if (!o) {
		let e = le(l);
		if (e) return u(e, !0);
	}
	let d = await V(), f = r === "all" ? ["movie", "tv"] : [r === "movie" ? "movie" : "tv"], p = /* @__PURE__ */ new Map(), m = (e, t, n, r) => {
		if (!e?.id || !e.poster_path || (e.vote_count ?? 0) < K) return;
		let i = `${t}:${e.id}`, a = p.get(i);
		a || (a = se(e, t, d), p.set(i, a)), n && a.seeds.push({
			title: n,
			weight: r
		});
	};
	(await Promise.allSettled(s.map((e) => re(e.item.tmdbId, X(e.item))))).forEach((e, t) => {
		if (e.status !== "fulfilled") return;
		let n = s[t], r = X(n.item);
		if (f.includes(r)) for (let t of e.value) m(t, r, n.item.title, n.weight);
	});
	let h = T(t, 3);
	if (h.length) {
		let e = [];
		for (let t of f) for (let n of [1, 2]) e.push((async () => {
			let e = await H(t), r = h.map((t) => e.get(t.name.toLowerCase())).filter(Boolean);
			return {
				mediaType: t,
				raws: await U(t, r, { page: n })
			};
		})());
		for (let t of await Promise.allSettled(e)) if (t.status === "fulfilled") for (let e of t.value.raws) m(e, t.value.mediaType, null, 0);
	}
	let g = oe(e), _ = [];
	for (let e of p.values()) {
		if (Q(g, e)) continue;
		let r = e.seeds.reduce((e, t) => e + t.weight, 0), i = E(e.genres, t), a = e.tmdbRating ? (e.tmdbRating - 6.5) * .12 : 0;
		e.score = r * 1.2 + i + a, !(e.score <= 0) && (e.why = e.seeds.length ? {
			genres: [],
			because: [...new Set(e.seeds.map((e) => e.title))].slice(0, 2)
		} : D(e.genres, t, n), _.push(e));
	}
	_.sort((e, t) => t.score - e.score);
	let v = _.slice(0, Y);
	return ue(l, v), u(v, !1);
}
//#endregion
//#region client/api.js
async function pe(e) {
	let t = {
		title: e.title,
		type: e.type,
		status: "planned",
		tmdbId: e.tmdbId,
		posterUrl: W(e.posterPath),
		year: e.year,
		tmdbRating: e.tmdbRating,
		genres: e.genres
	}, n;
	try {
		n = await ie(e.tmdbId, e.mediaType);
	} catch {
		return t;
	}
	let r = (n.genres ?? []).map((e) => e.name).filter(Boolean);
	return r.length && (t.genres = r), e.mediaType === "movie" ? n.runtime && (t.runtime = n.runtime) : (n.number_of_seasons && (t.seasons = n.number_of_seasons), n.number_of_episodes && (t.episodes = n.number_of_episodes), n.number_of_episodes && n.episode_run_time?.length && (t.showRuntime = n.number_of_episodes * n.episode_run_time[0]), t.seasonProgress = (n.seasons ?? []).filter((e) => e.season_number > 0 && e.episode_count > 0).sort((e, t) => e.season_number - t.season_number).map((e) => ({
		seasonNumber: e.season_number,
		name: e.name || `Season ${e.season_number}`,
		episodeCount: e.episode_count,
		watched: 0
	}))), t;
}
async function me(e) {
	return j().createItem(await pe(e));
}
//#endregion
//#region native/icons.js
var he = { refresh: "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" }, ge = (e) => c("svg", {
	viewBox: "0 0 24 24",
	fill: "none",
	stroke: "currentColor",
	"stroke-width": e.sw ?? 2,
	"stroke-linecap": "round",
	"stroke-linejoin": "round",
	"aria-hidden": "true"
}, [c("path", { d: he[e.name] ?? "" })]);
ge.props = ["name", "sw"];
//#endregion
//#region client/RecCard.vue
var _e = { class: "relative aspect-[2/3] bg-slate-100 dark:bg-slate-700/60" }, ve = ["src", "alt"], ye = {
	key: 1,
	class: "w-full h-full flex items-center justify-center text-slate-300 dark:text-slate-600"
}, be = {
	key: 2,
	class: "absolute top-1.5 right-1.5 inline-flex items-center gap-0.5 rounded-full bg-black/65 px-1.5 py-0.5 text-[11px] font-medium text-amber-300 backdrop-blur-sm"
}, xe = { class: "flex flex-1 flex-col gap-1.5 p-2.5" }, Se = { class: "min-w-0" }, Ce = ["title"], we = {
	key: 0,
	class: "text-xs text-slate-400 dark:text-slate-500"
}, Te = {
	key: 0,
	class: "text-[11px] leading-snug text-indigo-600/90 dark:text-indigo-400/90 line-clamp-2"
}, Ee = {
	key: 1,
	class: "text-[11px] text-slate-400 dark:text-slate-500 truncate"
}, De = ["disabled"], Oe = {
	__name: "RecCard",
	props: {
		title: {
			type: String,
			required: !0
		},
		year: {
			type: [Number, String],
			default: null
		},
		poster: {
			type: String,
			default: null
		},
		rating: {
			type: Number,
			default: null
		},
		genres: {
			type: Array,
			default: () => []
		},
		why: {
			type: Object,
			default: null
		},
		actionLabel: {
			type: String,
			required: !0
		},
		busy: {
			type: Boolean,
			default: !1
		},
		danger: {
			type: Boolean,
			default: !1
		},
		compact: {
			type: Boolean,
			default: !1
		}
	},
	emits: ["action"],
	setup(e) {
		let t = e, n = () => t.why ? t.why.because?.length ? `Because you watched ${t.why.because.join(" and ")}` : t.why.genres?.length ? `Matches your ${t.why.genres.join(" + ")} streak` : null : null;
		return (t, s) => (u(), i("article", { class: l(["group flex flex-col rounded-xl overflow-hidden bg-white/70 dark:bg-slate-800/70 border border-white/60 dark:border-white/8 shadow-sm transition-all duration-200 ease-out hover:-translate-y-0.5 hover:shadow-md", e.compact ? "w-36 shrink-0" : ""]) }, [a("div", _e, [e.poster ? (u(), i("img", {
			key: 0,
			src: e.poster,
			alt: e.title,
			loading: "lazy",
			class: "w-full h-full object-cover"
		}, null, 8, ve)) : (u(), i("div", ye, [...s[1] ||= [a("svg", {
			class: "w-8 h-8",
			fill: "none",
			stroke: "currentColor",
			"stroke-width": "1.5",
			viewBox: "0 0 24 24"
		}, [a("path", {
			"stroke-linecap": "round",
			"stroke-linejoin": "round",
			d: "M3.75 6.75h16.5v10.5H3.75zM3.75 10.5h16.5M8.25 6.75v10.5"
		})], -1)]])), e.rating ? (u(), i("span", be, [s[2] ||= a("svg", {
			class: "w-2.5 h-2.5 fill-current",
			viewBox: "0 0 24 24"
		}, [a("path", { d: "M12 3.5l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9 6.8 19.6l1-5.8-4.3-4.1 5.9-.9z" })], -1), o(" " + p(e.rating), 1)])) : r("", !0)]), a("div", xe, [
			a("div", Se, [a("h4", {
				class: "truncate text-sm font-medium text-slate-900 dark:text-white",
				title: e.title
			}, p(e.title), 9, Ce), e.year ? (u(), i("p", we, p(e.year), 1)) : r("", !0)]),
			n() ? (u(), i("p", Te, p(n()), 1)) : r("", !0),
			e.genres.length && !e.compact ? (u(), i("p", Ee, p(e.genres.slice(0, 3).join(" · ")), 1)) : r("", !0),
			a("button", {
				onClick: s[0] ||= (e) => t.$emit("action"),
				disabled: e.busy,
				class: l(["nuc-press mt-auto cursor-pointer w-full rounded-lg px-2 py-1.5 text-xs font-medium text-white transition-colors disabled:cursor-wait disabled:opacity-60", e.danger ? "bg-red-600/90 hover:bg-red-500" : "bg-indigo-600 hover:bg-indigo-500"])
			}, p(e.busy ? "Working…" : e.actionLabel), 11, De)
		])], 2));
	}
}, ke = { class: "glass rounded-2xl p-4 flex flex-col gap-4" }, Ae = { class: "flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between" }, je = { class: "min-w-0" }, Me = {
	key: 0,
	class: "mt-0.5 text-xs text-slate-400 dark:text-slate-500"
}, Ne = { class: "text-slate-500 dark:text-slate-400 font-medium" }, Pe = {
	key: 1,
	class: "mt-0.5 text-xs text-slate-400 dark:text-slate-500"
}, Fe = {
	key: 2,
	class: "mt-0.5 text-xs text-slate-400 dark:text-slate-500"
}, Ie = { class: "inline-flex items-center gap-0.5 bg-black/[0.04] dark:bg-white/5 rounded-xl p-1 shrink-0 self-start sm:self-auto" }, Le = ["onClick"], Re = {
	key: 0,
	class: "text-sm text-slate-500 dark:text-slate-400"
}, ze = { class: "flex flex-col gap-2" }, Be = { class: "flex items-baseline justify-between gap-3" }, Ve = {
	key: 0,
	class: "hidden sm:block text-xs text-slate-400 dark:text-slate-500 truncate"
}, He = {
	key: 0,
	class: "text-sm text-slate-400 dark:text-slate-500"
}, Ue = {
	key: 1,
	class: "text-xs text-amber-600 dark:text-amber-400"
}, We = { class: "flex flex-col gap-2" }, Ge = { class: "flex items-center justify-between gap-3" }, Ke = { class: "flex items-center gap-1.5 shrink-0" }, qe = ["disabled", "title"], Je = {
	key: 0,
	class: "text-xs text-slate-400 dark:text-slate-500"
}, Ye = {
	key: 1,
	class: "text-xs text-amber-600 dark:text-amber-400"
}, Xe = {
	key: 2,
	class: "text-sm text-slate-400 dark:text-slate-500"
}, Ze = {
	key: 3,
	class: "text-sm text-slate-400 dark:text-slate-500"
}, Qe = {
	__name: "watchlistSurface",
	props: {
		items: {
			type: Array,
			default: () => []
		},
		placement: {
			type: String,
			default: "tab"
		}
	},
	emits: ["changed"],
	setup(c, { emit: g }) {
		let _ = c, v = g, y = t(() => _.placement === "panel"), b = t(() => y.value ? 6 : 12), x = d("all"), S = [
			{
				key: "all",
				label: "All"
			},
			{
				key: "movie",
				label: "Movies"
			},
			{
				key: "show",
				label: "Shows"
			}
		], C = t(() => ee(_.items)), w = t(() => te(C.value)), E = t(() => T(w.value, 4)), D = t(() => C.value.filter((e) => e.weight > 0).slice(0, 3).map((e) => e.item.title)), O = t(() => ne(_.items, {
			affinity: w.value,
			signals: C.value,
			type: x.value,
			limit: b.value
		})), k = t(() => C.value.length > 0), A = t(() => w.value.size > 0), M = d([]), N = d(!1), F = d(null), I = d(0), L = d(0);
		async function R(e = !1) {
			if (!k.value) {
				M.value = [], L.value = 0;
				return;
			}
			N.value = !0, F.value = null;
			try {
				e && de();
				let t = await fe(_.items, {
					affinity: w.value,
					signals: C.value,
					type: x.value,
					limit: b.value,
					offset: I.value,
					force: e
				});
				M.value = t.results, L.value = t.poolSize;
			} catch (e) {
				M.value = [], L.value = 0, F.value = e instanceof P ? "no-key" : "failed";
			} finally {
				N.value = !1;
			}
		}
		function z() {
			I.value += b.value, R(!1);
		}
		let B = t(() => L.value > b.value), V = t(() => F.value === "no-key" ? null : F.value ? "retry" : B.value ? "rotate" : null), H = {
			retry: "Try TMDb again",
			rotate: "Show different suggestions"
		};
		function re() {
			V.value === "retry" ? (I.value = 0, R(!0)) : V.value === "rotate" && z();
		}
		let U = t(() => [x.value, C.value.filter((e) => e.item.tmdbId && e.weight > 0).slice(0, 4).map((e) => e.item.tmdbId).join(",")].join("|")), ie = t(() => `${U.value}|${_.items.length}`);
		h(U, () => {
			I.value = 0;
		}), h(ie, () => R(!1), { immediate: !0 });
		let G = d(/* @__PURE__ */ new Set()), K = d(/* @__PURE__ */ new Set());
		async function q(e) {
			if (!G.value.has(e.key)) {
				G.value = new Set(G.value).add(e.key), K.value = new Set([...K.value].filter((t) => t !== e.key));
				try {
					await me(e), M.value = M.value.filter((t) => t.key !== e.key), v("changed");
				} catch {
					K.value = new Set(K.value).add(e.key);
				} finally {
					let t = new Set(G.value);
					t.delete(e.key), G.value = t;
				}
			}
		}
		let J = d(/* @__PURE__ */ new Set());
		async function Y(e) {
			if (!J.value.has(e._id)) {
				J.value = new Set(J.value).add(e._id);
				try {
					await j().updateItem(e._id, { status: "watching" }), v("changed");
				} catch {} finally {
					let t = new Set(J.value);
					t.delete(e._id), J.value = t;
				}
			}
		}
		let X = t(() => y.value ? "flex gap-3 overflow-x-auto no-scrollbar pb-1 -mx-1 px-1" : "grid gap-3 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4");
		return (t, c) => (u(), i("section", ke, [a("div", Ae, [a("div", je, [c[1] ||= a("h2", { class: "text-base font-semibold text-slate-900 dark:text-white" }, "For You", -1), E.value.length ? (u(), i("p", Me, [c[0] ||= o(" Lately you've been into ", -1), a("span", Ne, p(E.value.map((e) => e.name).join(" · ")), 1)])) : k.value ? (u(), i("p", Pe, " Your finished titles have no genres yet — hit Refresh on the watchlist to fill them in. ")) : (u(), i("p", Fe, " Mark something completed and this starts working. "))]), a("div", Ie, [(u(), i(e, null, f(S, (e) => a("button", {
			key: e.key,
			onClick: (t) => x.value = e.key,
			class: l(["cursor-pointer whitespace-nowrap px-2.5 py-1 rounded-lg text-xs font-medium transition-all", x.value === e.key ? "bg-white dark:bg-white/15 text-slate-900 dark:text-white shadow-sm" : "text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"])
		}, p(e.label), 11, Le)), 64))])]), k.value ? (u(), i(e, { key: 1 }, [a("div", ze, [
			a("div", Be, [c[2] ||= a("h3", { class: "text-sm font-semibold text-slate-700 dark:text-slate-200" }, "Up next from your list", -1), D.value.length ? (u(), i("span", Ve, " because you watched " + p(D.value.join(", ")), 1)) : r("", !0)]),
			O.value.results.length ? A.value ? r("", !0) : (u(), i("p", Ue, " Ordered by rating only for now: none of your finished titles carry genres yet. ")) : (u(), i("p", He, " Nothing planned" + p(x.value === "all" ? "" : ` in ${x.value === "movie" ? "movies" : "shows"}`) + " — add something and it'll be ranked here. ", 1)),
			O.value.results.length ? (u(), i("div", {
				key: 2,
				class: l(X.value)
			}, [(u(!0), i(e, null, f(O.value.results, (e) => (u(), n(Oe, {
				key: e.item._id,
				title: e.item.title,
				year: e.item.year,
				poster: e.item.posterUrl,
				rating: e.item.rating ?? e.item.tmdbRating,
				genres: e.item.genres,
				why: e.why,
				compact: y.value,
				"action-label": "Start watching",
				busy: J.value.has(e.item._id),
				onAction: (t) => Y(e.item)
			}, null, 8, [
				"title",
				"year",
				"poster",
				"rating",
				"genres",
				"why",
				"compact",
				"busy",
				"onAction"
			]))), 128))], 2)) : r("", !0)
		]), a("div", We, [
			a("div", Ge, [c[4] ||= a("h3", { class: "text-sm font-semibold text-slate-700 dark:text-slate-200" }, "New to you", -1), a("div", Ke, [c[3] ||= a("span", { class: "text-xs text-slate-400 dark:text-slate-500" }, "from TMDb", -1), a("button", {
				onClick: re,
				disabled: N.value || !V.value,
				title: H[V.value] ?? "Nothing more to suggest right now",
				class: "nuc-press cursor-pointer h-7 px-1.5 rounded-lg text-slate-400 dark:text-slate-500 hover:text-slate-900 dark:hover:text-white hover:bg-black/5 dark:hover:bg-white/8 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
			}, [s(m(ge), {
				name: "refresh",
				class: l(["w-3.5 h-3.5", N.value ? "animate-spin" : ""])
			}, null, 8, ["class"])], 8, qe)])]),
			F.value === "no-key" ? (u(), i("p", Je, " TMDb isn't configured for this install, so there's nothing to discover from. The ranking of your own list above works without it. ")) : F.value ? (u(), i("p", Ye, " Couldn't reach TMDb. Use the retry button above. ")) : N.value && !M.value.length ? (u(), i("p", Xe, " Looking for something new… ")) : M.value.length ? r("", !0) : (u(), i("p", Ze, " Nothing new to suggest right now — everything close to your recent watching is already on your list. ")),
			M.value.length ? (u(), i("div", {
				key: 4,
				class: l(X.value)
			}, [(u(!0), i(e, null, f(M.value, (e) => (u(), n(Oe, {
				key: e.key,
				title: e.title,
				year: e.year,
				poster: m(W)(e.posterPath, "w342"),
				rating: e.tmdbRating,
				genres: e.genres,
				why: e.why,
				compact: y.value,
				"action-label": K.value.has(e.key) ? "Retry" : "Add to list",
				busy: G.value.has(e.key),
				danger: K.value.has(e.key),
				onAction: (t) => q(e)
			}, null, 8, [
				"title",
				"year",
				"poster",
				"rating",
				"genres",
				"why",
				"compact",
				"action-label",
				"busy",
				"danger",
				"onAction"
			]))), 128))], 2)) : r("", !0)
		])], 64)) : (u(), i("p", Re, " Once you've finished a few things, this reads their genres — weighted by how recently you watched them and how you rated them — and uses that to rank your backlog and find new titles. "))]));
	}
}, $e = `nucleus-plugin-${_.id}`, $ = document.getElementById($e);
$ || ($ = document.createElement("style"), $.id = $e, document.head.appendChild($)), $.textContent = g;
var { bundle: et, ...tt } = _.extensions.watchlistSurface, nt = {
	...tt,
	component: Qe,
	connect: M
};
//#endregion
export default nt;
