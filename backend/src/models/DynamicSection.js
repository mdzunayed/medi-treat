const mongoose = require('mongoose');

// One content element inside a dynamic home section. Embedded (no own _id);
// `itemId` is a client-generated stable key used for image public_ids.
const ContentItemSchema = new mongoose.Schema(
  {
    itemId: { type: String, required: true },
    title: { type: String, required: true, trim: true },
    subtitle: { type: String, default: null },
    imageUrl: { type: String, required: true },
    priceTag: { type: String, default: null },
    // Client-side route string, e.g. "new_request", "service:<id>",
    // "activities:tracking", or an https:// URL. Unknown values no-op.
    navigationRoute: { type: String, default: null },
    routeArguments: { type: Map, of: String, default: {} },
    // Optional per-card color overrides (admin "micro-branding"). Each is a
    // `#RRGGBB` hex string or null — null means "fall back to the client's
    // built-in theme token", so unset cards render exactly as before. The
    // Light/Dark pairs let a color stay accessible in both display modes; tag
    // colors are single values used in both.
    cardStyles: {
      cardBgLight: { type: String, default: null },
      cardBgDark: { type: String, default: null },
      accentColorLight: { type: String, default: null },
      accentColorDark: { type: String, default: null },
      tagBgColor: { type: String, default: null },
      tagTextColor: { type: String, default: null },
    },
  },
  { _id: false }
);

const DynamicSectionSchema = new mongoose.Schema(
  {
    // Stable natural key, e.g. "trending_doctors", "ramadan_packages".
    sectionKey: { type: String, required: true, unique: true, trim: true },
    titleEn: { type: String, required: true, trim: true },
    titleBn: { type: String, default: null },
    // Which reusable client template renders this section. The client skips
    // sections whose template it doesn't know, so new values can be added
    // here ahead of an app update.
    uiTemplate: {
      type: String,
      enum: [
        'HORIZONTAL_ROUND_AVATAR',
        'HORIZONTAL_PRODUCT_CARD',
        'GRID_2X2_TILES',
        'SINGLE_WIDE_BANNER',
      ],
      required: true,
    },
    // Ascending display order below the fixed Banners + Care Services blocks.
    orderIndex: { type: Number, required: true, index: true },
    isActive: { type: Boolean, default: true, index: true },
    // Optional section-container color overrides. `#RRGGBB` hex or null;
    // null ⇒ the client falls back to its built-in theme token.
    styleTokens: {
      titleColorLight: { type: String, default: null },
      titleColorDark: { type: String, default: null },
      sectionBackgroundColor: { type: String, default: null },
    },
    contentData: { type: [ContentItemSchema], default: [] },
  },
  { timestamps: true }
);

DynamicSectionSchema.set('toJSON', {
  virtuals: true,
  versionKey: false,
  transform: (_doc, ret) => {
    ret.id = ret._id.toString();
    delete ret._id;
    return ret;
  },
});

module.exports = mongoose.model('DynamicSection', DynamicSectionSchema);
