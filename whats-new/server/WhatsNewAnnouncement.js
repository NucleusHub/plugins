import mongoose from 'mongoose'

const featureSchema = new mongoose.Schema({
  title: { type: Map, of: String, default: () => ({}) },
  body:  { type: Map, of: String, default: () => ({}) },
  icon:  { type: String, default: null },
}, { _id: false })

const entrySchema = new mongoose.Schema({
  app:      { type: String, required: true },
  version:  { type: String, default: '' },
  features: { type: [featureSchema], default: [] },
}, { _id: false })

const announcementSchema = new mongoose.Schema({
  version:     { type: String, required: true },
  published:   { type: Boolean, default: false },
  publishedAt: { type: Date, default: null },
  entries:     { type: [entrySchema], default: [] },
}, { timestamps: true })

export default mongoose.model('WhatsNewAnnouncement', announcementSchema)
