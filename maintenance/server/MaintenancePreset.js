import mongoose from 'mongoose'

const maintenancePresetSchema = new mongoose.Schema({
  key:     { type: String, required: true, unique: true },
  builtin: { type: Boolean, default: false },
  order:   { type: Number, default: 100 },
  level:   { type: String, default: 'warning' },
  title:   { type: Map, of: String, default: () => ({}) },
  message: { type: Map, of: String, default: () => ({}) },
}, { timestamps: true })

export default mongoose.model('MaintenancePreset', maintenancePresetSchema)
