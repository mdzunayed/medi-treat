const express = require('express');
const PromoBanner = require('../models/PromoBanner');
const {
  upload,
  storeImage,
  removeImage,
} = require('../middleware/upload');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || 'http://localhost:4000';
const imageUrl = (filename) => filename ? `${PUBLIC_BASE_URL}/uploads/${filename}` : null;

function decorate(doc) {
  const obj = doc.toJSON();
  if (obj.imageUrl && !/^https?:\/\//i.test(obj.imageUrl)) {
    obj.imageUrl = imageUrl(obj.imageUrl);
  }
  return obj;
}

// Accept gradientColors from multipart (a JSON string) or JSON body (an
// array). Returns undefined when nothing usable was sent so callers can
// fall back to the schema default / the existing value.
function parseGradient(raw) {
  if (Array.isArray(raw)) {
    return raw.map((c) => String(c)).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim().length) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) return parsed.map((c) => String(c)).filter(Boolean);
    } catch (_e) {
      // Not JSON — treat a bare comma-separated string as a fallback.
      const parts = raw.split(',').map((c) => c.trim()).filter(Boolean);
      if (parts.length) return parts;
    }
  }
  return undefined;
}

function parseBool(raw, fallback) {
  if (raw === undefined || raw === null || raw === '') return fallback;
  return raw === true || raw === 'true' || raw === '1' || raw === 1;
}

// GET /api/promo-banners?active=1  (public — the client home slider reads this)
router.get('/', async (req, res) => {
  try {
    const filter = {};
    if (req.query.active === '1' || req.query.active === 'true') {
      filter.isActive = true;
    }
    const docs = await PromoBanner.find(filter).sort({ priorityOrder: 1, createdAt: -1 });
    res.json(docs.map(decorate));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /api/promo-banners  (admin; multipart: fields + optional image)
router.post('/', requireRole('admin'), upload.single('image'), async (req, res) => {
  try {
    const { tagText, title, buttonText } = req.body;
    if (!tagText || !tagText.trim()) return res.status(400).json({ message: 'tagText is required' });
    if (!title || !title.trim()) return res.status(400).json({ message: 'title is required' });
    if (!buttonText || !buttonText.trim()) return res.status(400).json({ message: 'buttonText is required' });

    // Default the new banner to the end of the current order.
    const last = await PromoBanner.findOne().sort({ priorityOrder: -1 }).select('priorityOrder');
    const nextOrder = last ? last.priorityOrder + 1 : 0;

    const gradientColors = parseGradient(req.body.gradientColors);

    const doc = await PromoBanner.create({
      tagText: tagText.trim(),
      title: title.trim(),
      buttonText: buttonText.trim(),
      ...(gradientColors ? { gradientColors } : {}),
      priorityOrder: req.body.priorityOrder !== undefined ? Number(req.body.priorityOrder) : nextOrder,
      isActive: parseBool(req.body.isActive, true),
    });

    if (req.file) {
      doc.imageUrl = await storeImage(req.file.buffer, doc._id.toString());
      await doc.save();
    }

    res.status(201).json(decorate(doc));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PATCH /api/promo-banners/reorder  { ids: [...] }  (admin)
// Renumbers priorityOrder to match the supplied id order (0..n-1).
router.patch('/reorder', requireRole('admin'), async (req, res) => {
  try {
    const { ids } = req.body;
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ message: 'ids must be a non-empty array' });
    }
    const ops = ids.map((id, index) => ({
      updateOne: { filter: { _id: id }, update: { $set: { priorityOrder: index } } },
    }));
    await PromoBanner.bulkWrite(ops);
    const docs = await PromoBanner.find().sort({ priorityOrder: 1, createdAt: -1 });
    res.json(docs.map(decorate));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PUT /api/promo-banners/:id  (admin; multipart: fields + optional new image)
router.put('/:id', requireRole('admin'), upload.single('image'), async (req, res) => {
  try {
    const doc = await PromoBanner.findById(req.params.id);
    if (!doc) return res.status(404).json({ message: 'Banner not found' });

    const { tagText, title, buttonText } = req.body;
    if (tagText !== undefined) {
      if (!tagText.trim()) return res.status(400).json({ message: 'tagText cannot be empty' });
      doc.tagText = tagText.trim();
    }
    if (title !== undefined) {
      if (!title.trim()) return res.status(400).json({ message: 'title cannot be empty' });
      doc.title = title.trim();
    }
    if (buttonText !== undefined) {
      if (!buttonText.trim()) return res.status(400).json({ message: 'buttonText cannot be empty' });
      doc.buttonText = buttonText.trim();
    }
    const gradientColors = parseGradient(req.body.gradientColors);
    if (gradientColors) doc.gradientColors = gradientColors;
    if (req.body.priorityOrder !== undefined) doc.priorityOrder = Number(req.body.priorityOrder);
    if (req.body.isActive !== undefined) doc.isActive = parseBool(req.body.isActive, doc.isActive);

    if (req.file) {
      doc.imageUrl = await storeImage(req.file.buffer, doc._id.toString());
    }

    await doc.save();
    res.json(decorate(doc));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PATCH /api/promo-banners/:id/status  { isActive: boolean }  (admin)
router.patch('/:id/status', requireRole('admin'), async (req, res) => {
  try {
    if (req.body.isActive === undefined) {
      return res.status(400).json({ message: 'isActive is required' });
    }
    const isActive = parseBool(req.body.isActive, true);
    const doc = await PromoBanner.findByIdAndUpdate(
      req.params.id,
      { isActive },
      { new: true }
    );
    if (!doc) return res.status(404).json({ message: 'Banner not found' });
    res.json(decorate(doc));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// DELETE /api/promo-banners/:id  (admin)
router.delete('/:id', requireRole('admin'), async (req, res) => {
  try {
    const doc = await PromoBanner.findByIdAndDelete(req.params.id);
    if (!doc) return res.status(404).json({ message: 'Banner not found' });
    await removeImage(doc._id.toString());
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
