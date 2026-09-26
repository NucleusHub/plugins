import mongoose from 'mongoose'

const schema = new mongoose.Schema(
  {
    scope: { type: String, enum: ['group', 'network'], default: 'network' },
  },
  { timestamps: true },
)

export default mongoose.models.InCommonConfig || mongoose.model('InCommonConfig', schema)
