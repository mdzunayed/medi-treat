const mongoose = require('mongoose');

const PromoBannerSchema = new mongoose.Schema(
  {
    tagText: { type: String, required: true, trim: true },
    title: { type: String, required: true, trim: true },
    buttonText: { type: String, required: true, trim: true },
    imageUrl: { type: String, default: null },
    // Two (or more) HEX stops driving the card's background gradient, e.g.
    // ['#4C1D95', '#8B5CF6']. Stored verbatim; the client parses them.
    gradientColors: {
      type: [String],
      default: ['#4C1D95', '#8B5CF6'],
    },
    // Ascending display order in the Home slider. Lower shows first.
    priorityOrder: { type: Number, default: 0, index: true },
    isActive: { type: Boolean, default: true, index: true },
  },
  { timestamps: true }
);

PromoBannerSchema.set('toJSON', {
  virtuals: true,
  versionKey: false,
  transform: (_doc, ret) => {
    ret.id = ret._id.toString();
    delete ret._id;
    return ret;
  },
});

module.exports = mongoose.model('PromoBanner', PromoBannerSchema);
