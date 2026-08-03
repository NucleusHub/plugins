// The binder permission model, replacing Dex's personal-only default.
//
// Imported by the Dex server at startup (pluginHost.js → setBinderAccessPolicy)
// because the manifest declares `extensions.dexBinderAccess`. Dex's binder
// routes never change: they ask this policy who may see a binder and what role
// the caller has, and the capability table in Dex's utils/binderAccess.js turns
// that role into permissions.
//
// The model follows Orbit's, which is the established Nucleus shape for shared
// content:
//   • PERSONAL — groupId null, owned by profileId. Only the owner, unless they
//     hand out grants.
//   • SHARED   — explicit per-profile grants in `shares[]`, each with a role.
//   • GROUP    — groupId set. Every member of a group with `sharedDex` on can
//     open it, exactly like Orbit's immutable "Group - {name}" directory. The
//     Nucleus admin creates it; members contribute to it.
//
// Roles, weakest first: viewer → contributor → admin. The creator is always
// `owner`, which outranks all of them and can't be revoked out from under them.
//
// Mongoose is resolved from the importing app's node_modules (the same way
// Dex's own models do it), so this file needs no dependencies of its own.
import mongoose from 'mongoose'

const sid = (v) => (v == null ? '' : String(v))

const VALID_ROLES = new Set(['viewer', 'contributor', 'admin'])

// Group membership, read straight off the shared `groups` collection the
// auth-server owns — the same read-only mirror pattern Orbit and Prism use.
// A short TTL cache keeps a page of nine pockets from issuing nine lookups.
const TTL_MS = 10_000
const groupCache = new Map() // profileId → { at, ids: string[] }

async function sharedDexGroupIds(profileId) {
  const pid = sid(profileId)
  const hit = groupCache.get(pid)
  const now = Date.now()
  if (hit && now - hit.at < TTL_MS) return hit.ids

  const db = mongoose.connection?.db
  if (!db) return []
  const rows = await db
    .collection('groups')
    .find({ memberIds: pid, sharedDex: true }, { projection: { _id: 1 } })
    .toArray()
  const ids = rows.map((g) => String(g._id))
  groupCache.set(pid, { at: now, ids })
  return ids
}

const policy = {
  id: 'dex-shared-binders',

  // Every binder this profile may open: their own, ones shared with them
  // directly, and the group binders of every sharedDex group they're in.
  async listFilter(profileId) {
    const groupIds = await sharedDexGroupIds(profileId)
    const or = [
      { profileId },
      { 'shares.profileId': profileId },
    ]
    if (groupIds.length) {
      or.push({ groupId: { $in: groupIds.map((id) => new mongoose.Types.ObjectId(id)) } })
    }
    return { $or: or }
  },

  // The caller's role on a binder, or null when they may not see it at all.
  // Highest applicable role wins: an explicit admin grant on a group binder
  // beats the contributor role membership alone would give.
  async roleFor(binder, profileId) {
    if (!binder) return null
    const me = sid(profileId)

    if (sid(binder.profileId) === me) return 'owner'

    let best = null
    const grant = (binder.shares ?? []).find((s) => sid(s.profileId) === me)
    if (grant && VALID_ROLES.has(grant.role)) best = grant.role

    if (binder.groupId) {
      const groupIds = await sharedDexGroupIds(profileId)
      if (groupIds.includes(sid(binder.groupId))) {
        // A group binder is a shared workspace: members contribute by default.
        // Renaming or re-sharing it still needs an explicit admin grant.
        best = rank(best) >= rank('contributor') ? best : 'contributor'
      }
    }

    return best
  },
}

const RANK = { viewer: 1, contributor: 2, admin: 3, owner: 4 }
const rank = (r) => RANK[r] || 0

export default policy
