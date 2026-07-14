const express = require('express');
const DynamicSection = require('../models/DynamicSection');
const {
  upload,
  storeImage,
  removeImage,
} = require('../middleware/upload');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || 'http://localhost:4000';
const absoluteUrl = (filename) => filename ? `${PUBLIC_BASE_URL}/uploads/${filename}` : null;

// Deterministic image public_id for a content item; also matched on delete.
const itemImageId = (itemId) => `hsitem_${itemId}`;

function decorate(doc) {
  const obj = doc.toJSON();
  obj.contentData = (obj.contentData || []).map((item) => {
    if (item.imageUrl && !/^https?:\/\//i.test(item.imageUrl)) {
      return { ...item, imageUrl: absoluteUrl(item.imageUrl) };
    }
    return item;
  });
  return obj;
}

function parseBool(raw, fallback) {
  if (raw === undefined || raw === null || raw === '') return fallback;
  return raw === true || raw === 'true' || raw === '1' || raw === 1;
}

// The optional color-override keys, per level.
const SECTION_STYLE_KEYS = ['titleColorLight', 'titleColorDark', 'sectionBackgroundColor'];
const CARD_STYLE_KEYS = [
  'cardBgLight', 'cardBgDark', 'accentColorLight', 'accentColorDark',
  'tagBgColor', 'tagTextColor',
];

// Normalizes a color to "#RRGGBB". Empty/null/undefined => null (unset, so the
// client falls back to its theme token). Accepts #RGB / #RRGGBB, case- and
// hash-insensitive. Throws a client-safe Error on a malformed value; `label`
// names the offending field.
function sanitizeHex(value, label) {
  if (value === undefined || value === null) return null;
  const s = String(value).trim();
  if (!s) return null;
  const hex = s.startsWith('#') ? s.slice(1) : s;
  if (/^[0-9a-fA-F]{3}$/.test(hex)) {
    const [r, g, b] = hex;
    return `#${(r + r + g + g + b + b).toUpperCase()}`;
  }
  if (/^[0-9a-fA-F]{6}$/.test(hex)) {
    return `#${hex.toUpperCase()}`;
  }
  throw new Error(`${label} must be a hex color like #RRGGBB`);
}

// Sanitizes a style-token object against a known key set. Returns undefined
// when the object is absent (so the caller leaves the schema default nulls in
// place); throws on a non-object or malformed hex within.
function sanitizeTokens(raw, keys, label) {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error(`${label} must be an object`);
  }
  const out = {};
  for (const key of keys) {
    out[key] = sanitizeHex(raw[key], `${label}.${key}`);
  }
  return out;
}

// Accepts contentData as an array or a JSON string. Validates each item and
// coerces routeArguments values to strings. Throws Error with a client-safe
// message on invalid input (callers translate to 400).
function sanitizeItems(raw) {
  let items = raw;
  if (typeof raw === 'string') {
    try {
      items = JSON.parse(raw);
    } catch (_e) {
      throw new Error('contentData must be an array or JSON array string');
    }
  }
  if (!Array.isArray(items)) {
    throw new Error('contentData must be an array');
  }
  return items.map((item, i) => {
    if (!item || typeof item !== 'object') {
      throw new Error(`contentData[${i}] must be an object`);
    }
    const title = typeof item.title === 'string' ? item.title.trim() : '';
    if (!title) throw new Error(`contentData[${i}].title is required`);
    const imageUrl = typeof item.imageUrl === 'string' ? item.imageUrl.trim() : '';
    if (!imageUrl) throw new Error(`contentData[${i}].imageUrl is required`);

    const routeArguments = {};
    if (item.routeArguments && typeof item.routeArguments === 'object') {
      for (const [k, v] of Object.entries(item.routeArguments)) {
        if (v !== undefined && v !== null) routeArguments[k] = String(v);
      }
    }

    const cardStyles = sanitizeTokens(
      item.cardStyles, CARD_STYLE_KEYS, `contentData[${i}].cardStyles`);

    return {
      itemId: item.itemId ? String(item.itemId) : String(i),
      title,
      subtitle: item.subtitle ? String(item.subtitle) : null,
      imageUrl,
      priceTag: item.priceTag ? String(item.priceTag) : null,
      navigationRoute: item.navigationRoute ? String(item.navigationRoute) : null,
      routeArguments,
      ...(cardStyles ? { cardStyles } : {}),
    };
  });
}

const UI_TEMPLATES = DynamicSection.schema.path('uiTemplate').enumValues;

// GET /api/home-sections?active=1  (public — the client home screen reads this)
router.get('/', async (req, res) => {
  try {
    const filter = {};
    if (req.query.active === '1' || req.query.active === 'true') {
      filter.isActive = true;
    }
    const docs = await DynamicSection.find(filter).sort({ orderIndex: 1, createdAt: -1 });
    res.json(docs.map(decorate));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /api/home-sections  (admin; JSON body)
router.post('/', requireRole('admin'), async (req, res) => {
  try {
    const { sectionKey, titleEn, uiTemplate } = req.body;
    if (!sectionKey || !String(sectionKey).trim()) {
      return res.status(400).json({ message: 'sectionKey is required' });
    }
    if (!titleEn || !String(titleEn).trim()) {
      return res.status(400).json({ message: 'titleEn is required' });
    }
    if (!UI_TEMPLATES.includes(uiTemplate)) {
      return res.status(400).json({ message: `uiTemplate must be one of: ${UI_TEMPLATES.join(', ')}` });
    }

    const key = String(sectionKey).trim();
    const existing = await DynamicSection.findOne({ sectionKey: key }).select('_id');
    if (existing) return res.status(409).json({ message: 'sectionKey already exists' });

    let contentData = [];
    let styleTokens;
    if (req.body.contentData !== undefined) {
      try {
        contentData = sanitizeItems(req.body.contentData);
      } catch (e) {
        return res.status(400).json({ message: e.message });
      }
    }
    if (req.body.styleTokens !== undefined) {
      try {
        styleTokens = sanitizeTokens(req.body.styleTokens, SECTION_STYLE_KEYS, 'styleTokens');
      } catch (e) {
        return res.status(400).json({ message: e.message });
      }
    }

    // Default the new section to the end of the current order.
    const last = await DynamicSection.findOne().sort({ orderIndex: -1 }).select('orderIndex');
    const nextOrder = last ? last.orderIndex + 1 : 0;

    const doc = await DynamicSection.create({
      sectionKey: key,
      titleEn: String(titleEn).trim(),
      titleBn: req.body.titleBn ? String(req.body.titleBn).trim() : null,
      uiTemplate,
      orderIndex: req.body.orderIndex !== undefined ? Number(req.body.orderIndex) : nextOrder,
      isActive: parseBool(req.body.isActive, true),
      contentData,
      ...(styleTokens ? { styleTokens } : {}),
    });

    res.status(201).json(decorate(doc));
  } catch (err) {
    if (err && err.code === 11000) {
      return res.status(409).json({ message: 'sectionKey already exists' });
    }
    res.status(500).json({ message: err.message });
  }
});

// PATCH /api/home-sections/reorder  { ids: [...] }  (admin)
// Renumbers orderIndex to match the supplied id order (0..n-1).
router.patch('/reorder', requireRole('admin'), async (req, res) => {
  try {
    const { ids } = req.body;
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ message: 'ids must be a non-empty array' });
    }
    const ops = ids.map((id, index) => ({
      updateOne: { filter: { _id: id }, update: { $set: { orderIndex: index } } },
    }));
    await DynamicSection.bulkWrite(ops);
    const docs = await DynamicSection.find().sort({ orderIndex: 1, createdAt: -1 });
    res.json(docs.map(decorate));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /api/home-sections/images  (admin; multipart: itemId + image)
// Upload-first flow: the admin dialog uploads each item image before the
// section itself is saved, then references the returned URL in contentData.
router.post('/images', requireRole('admin'), upload.single('image'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ message: 'image file is required' });
    const itemId = req.body.itemId && String(req.body.itemId).trim();
    if (!itemId) return res.status(400).json({ message: 'itemId is required' });

    const stored = await storeImage(req.file.buffer, itemImageId(itemId));
    const imageUrl = /^https?:\/\//i.test(stored) ? stored : absoluteUrl(stored);
    res.status(201).json({ imageUrl });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PUT /api/home-sections/:id  (admin; JSON body, partial update;
// contentData present ⇒ whole-array replace)
router.put('/:id', requireRole('admin'), async (req, res) => {
  try {
    const doc = await DynamicSection.findById(req.params.id);
    if (!doc) return res.status(404).json({ message: 'Section not found' });

    const { titleEn, titleBn, uiTemplate } = req.body;
    if (titleEn !== undefined) {
      if (!String(titleEn).trim()) return res.status(400).json({ message: 'titleEn cannot be empty' });
      doc.titleEn = String(titleEn).trim();
    }
    if (titleBn !== undefined) {
      doc.titleBn = titleBn ? String(titleBn).trim() : null;
    }
    if (uiTemplate !== undefined) {
      if (!UI_TEMPLATES.includes(uiTemplate)) {
        return res.status(400).json({ message: `uiTemplate must be one of: ${UI_TEMPLATES.join(', ')}` });
      }
      doc.uiTemplate = uiTemplate;
    }
    if (req.body.orderIndex !== undefined) doc.orderIndex = Number(req.body.orderIndex);
    if (req.body.isActive !== undefined) doc.isActive = parseBool(req.body.isActive, doc.isActive);
    if (req.body.styleTokens !== undefined) {
      try {
        doc.styleTokens = sanitizeTokens(req.body.styleTokens, SECTION_STYLE_KEYS, 'styleTokens');
      } catch (e) {
        return res.status(400).json({ message: e.message });
      }
    }
    if (req.body.contentData !== undefined) {
      try {
        doc.contentData = sanitizeItems(req.body.contentData);
      } catch (e) {
        return res.status(400).json({ message: e.message });
      }
    }

    await doc.save();
    res.json(decorate(doc));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PATCH /api/home-sections/:id/status  { isActive: boolean }  (admin)
router.patch('/:id/status', requireRole('admin'), async (req, res) => {
  try {
    if (req.body.isActive === undefined) {
      return res.status(400).json({ message: 'isActive is required' });
    }
    const isActive = parseBool(req.body.isActive, true);
    const doc = await DynamicSection.findByIdAndUpdate(
      req.params.id,
      { isActive },
      { new: true }
    );
    if (!doc) return res.status(404).json({ message: 'Section not found' });
    res.json(decorate(doc));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// DELETE /api/home-sections/:id  (admin)
router.delete('/:id', requireRole('admin'), async (req, res) => {
  try {
    const doc = await DynamicSection.findByIdAndDelete(req.params.id);
    if (!doc) return res.status(404).json({ message: 'Section not found' });
    // Best-effort cleanup of uploaded item images. Skips pasted external
    // URLs that never went through our upload pipeline.
    for (const item of doc.contentData || []) {
      const ours = item.imageUrl &&
        (!/^https?:\/\//i.test(item.imageUrl) || item.imageUrl.includes(`/${itemImageId(item.itemId)}`));
      if (ours) await removeImage(itemImageId(item.itemId));
    }
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
