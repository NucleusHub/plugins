import mongoose from 'mongoose'

const sid = (v) => (v == null ? '' : String(v))

const VALID_ROLES = new Set(['viewer', 'contributor', 'admin'])

const TTL_MS = 10_000
const groupCache = new Map()

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
        best = rank(best) >= rank('contributor') ? best : 'contributor'
      }
    }

    return best
  },
}

const RANK = { viewer: 1, contributor: 2, admin: 3, owner: 4 }
const rank = (r) => RANK[r] || 0

export default policy
