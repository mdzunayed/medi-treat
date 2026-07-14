const express = require('express');
const mongoose = require('mongoose');
const CareRequest = require('../models/CareRequest');
const Account = require('../models/Account');
const { attachDoctorToRequest } = require('../utils/doctorView');
const {
  safeEmitNotification,
  userRoomFor,
} = require('../services/notificationService');
const { sendHighPriorityPush } = require('../services/fcmService');
const { requireAccountId, attachAccountId } = require('../middleware/auth');
const paymentService = require('../services/paymentService');
const { DEPOSIT_AMOUNT, roundMoney } = require('../utils/money');

const router = express.Router();

// Base URL used to build gateway success/fail/cancel/IPN callbacks.
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || 'http://localhost:5000';

// Fan out an in-app + push notification to every admin that a paid booking
// is now awaiting care-management review. Best-effort: a notification
// failure must never tank the state transition that triggered it.
async function notifyAdminsBookingReady(io, doc) {
  try {
    const admins = await Account.find({ role: 'admin' }, '_id').lean();
    const title = 'New booking ready for review';
    const body =
      `${doc.patient_name} paid the ৳${DEPOSIT_AMOUNT} deposit for ` +
      `${doc.care_type}` +
      (doc.location_text ? ` in ${doc.location_text}` : '') +
      '.';
    const payload = {
      requestId: doc._id.toString(),
      patientName: doc.patient_name,
      careType: doc.care_type,
      deepLink: `/admin/booking-review/${doc._id.toString()}`,
    };
    await Promise.all(
      admins.map((a) =>
        safeEmitNotification(io, {
          recipientId: a._id,
          senderId: doc.patient_account_id || null,
          title,
          body,
          type: 'system_broadcast',
          payload,
        }),
      ),
    );
  } catch (e) {
    // Notification fan-out is best-effort — log and move on.
    console.warn('[notifications] admin booking-ready fan-out skipped:', e.message);
  }
}

// Fields the patient profile screen is allowed to mutate. Anything else in
// the PATCH body (role, status, password_hash, etc.) is dropped before we
// hit Mongoose so a malicious or buggy client can't escalate privileges.
const PATIENT_EDITABLE_FIELDS = ['full_name', 'email', 'phone'];

function pickPatientFields(body) {
  const out = {};
  for (const k of PATIENT_EDITABLE_FIELDS) {
    if (body[k] !== undefined && body[k] !== null) {
      out[k] = typeof body[k] === 'string' ? body[k].trim() : body[k];
    }
  }
  return out;
}

const TERMINAL = ['completed', 'cancelled', 'rejected'];

// Derive a coarse area from free-text location ("House 42, Dhanmondi" -> "Dhanmondi").
function areaFromLocation(location) {
  if (!location) return '';
  const parts = String(location).split(',');
  return parts[parts.length - 1].trim();
}

// Coerce an incoming coordinate to a finite Number, or null. Guards against
// an explicit `null` / '' becoming a bogus 0,0 (Gulf-of-Guinea) fix.
function coordOrNull(v) {
  if (v === undefined || v === null || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

// Normalise the optional care-recipient (dependent) block on a booking.
// Returns null for a self-booking; otherwise a clean snapshot the provider
// surfaces. A missing name collapses the whole block to null.
function pickCareRecipient(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const name = (raw.name ?? '').toString().trim();
  if (!name) return null;
  const str = (v) => {
    const s = (v ?? '').toString().trim();
    return s || null;
  };
  return {
    name,
    relationship: str(raw.relationship),
    medical_notes: str(raw.medical_notes),
  };
}

// POST /patient/requests — create a care request. Returns 201 + the row.
router.post('/requests', async (req, res) => {
  try {
    const b = req.body || {};
    if (!b.patient_name || !String(b.patient_name).trim()) {
      return res.status(400).json({ message: 'patient_name is required' });
    }
    if (!b.care_type || !String(b.care_type).trim()) {
      return res.status(400).json({ message: 'care_type is required' });
    }

    const doc = await CareRequest.create({
      patient_name: String(b.patient_name).trim(),
      patient_account_id: b.patient_account_id || '',
      patient_phone: b.patient_phone || '',
      care_type: String(b.care_type).trim(),
      offered_budget: Number(b.offered_budget) || 0,
      preferred_time: b.preferred_time || null,
      duration_hours: Number(b.duration_hours) || 1,
      condition_note: b.condition_note || '',
      location_text: b.location_text || '',
      area: b.area || areaFromLocation(b.location_text),
      latitude: coordOrNull(b.latitude),
      longitude: coordOrNull(b.longitude),
      care_recipient: pickCareRecipient(b.care_recipient),
      // Phase 1: the booking is NOT yet live. It stays `awaiting_deposit`
      // until the ৳100 confirmation deposit clears the gateway — only then
      // do we fan out to admins (see POST /requests/:id/deposit/*). This
      // keeps unpaid, abandoned bookings out of the triage queue.
      status: 'awaiting_deposit',
      urgency_level: b.urgency_level || (b.preferred_time ? 'medium' : 'high'),
    });

    res.status(201).json(doc.toJSON());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/cancel  { reason? }
//
// Patient-initiated cancellation from the "Under Review" queue. Only allowed
// BEFORE a field coordinator claims the dispatch — once it's `assigned` (or
// further), the patient can no longer pull it back unilaterally. Implemented
// as an atomic compare-and-swap guarded on the pre-assignment states so a
// cancel racing an admin assignment can't strand the request in a bad state.
router.post('/requests/:id/cancel', async (req, res) => {
  try {
    const { id } = req.params;
    if (!mongoose.isValidObjectId(id)) {
      return res.status(400).json({ message: 'Invalid request id' });
    }
    const reason =
      typeof (req.body && req.body.reason) === 'string'
        ? req.body.reason.trim()
        : '';

    const cancelled = await CareRequest.findOneAndUpdate(
      { _id: id, status: { $in: ['submitted', 'approved'] } },
      {
        $set: {
          status: 'cancelled',
          admin_note: reason
            ? `Cancelled by patient: ${reason}`
            : 'Cancelled by patient',
        },
      },
      { new: true },
    );

    if (!cancelled) {
      // Distinguish "gone" from "too late to cancel" so the UI can explain.
      const exists = await CareRequest.exists({ _id: id });
      return res.status(exists ? 409 : 404).json({
        message: exists
          ? 'This request can no longer be cancelled — a coordinator has already started working on it.'
          : 'Request not found',
      });
    }

    res.json(cancelled.toJSON());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// ---------------------------------------------------------------------------
// Two-phase confirmation payments (SSLCommerz, with simulated fallback).
// ---------------------------------------------------------------------------

// Ownership guard shared by every payment endpoint. Loads the request and
// rejects if the caller is not the booking patient. A request with a blank
// `patient_account_id` (legacy/anonymous) is treated as caller-owned so the
// flow still works in dev/seed data.
// Roles permitted to act on a booking they don't own (staff testing /
// operating a patient's checkout). NOTE: this intentionally lets admins and
// support members initiate/settle payments against ANY patient's booking in
// all environments — a deliberate access-control trade-off requested by the
// product owner. Every such cross-account access is logged below.
const STAFF_ROLES = new Set(['admin', 'support_member']);

// Resolve the caller's role. `attachAccountId` populates `req.accountRole`
// from the bearer token; fall back to a live DB lookup for header/query
// callers so a freshly-demoted account can't slip through on a stale token.
async function callerRole(req) {
  if (req.accountRole) return req.accountRole;
  if (!req.accountId) return null;
  const acct = await Account.findById(req.accountId, 'role');
  return acct ? acct.role : null;
}

async function loadOwnedRequest(req, res) {
  const { id } = req.params;
  if (!mongoose.isValidObjectId(id)) {
    res.status(400).json({ message: 'Invalid request id' });
    return null;
  }
  const doc = await CareRequest.findById(id);
  if (!doc) {
    res.status(404).json({ message: 'Request not found' });
    return null;
  }
  const isForeign =
    doc.patient_account_id &&
    req.accountId &&
    doc.patient_account_id.toString() !== req.accountId.toString();
  if (isForeign) {
    const role = await callerRole(req);
    if (!STAFF_ROLES.has(role)) {
      res.status(403).json({ message: 'Not your booking' });
      return null;
    }
    // Staff override — audit the cross-account access.
    console.warn(
      `[audit] staff cross-account booking access: role=${role} ` +
        `account=${req.accountId} booking=${doc._id} ` +
        `owner=${doc.patient_account_id} ${req.method} ${req.originalUrl}`,
    );
  }
  return doc;
}

// Build the SSLCommerz customer block from a request row.
function customerFromRequest(doc) {
  return {
    name: doc.patient_name,
    phone: doc.patient_phone || undefined,
    address: doc.location_text || undefined,
  };
}

// Atomically settle the Phase-1 deposit: awaiting_deposit -> reviewing.
// Idempotent — a duplicate IPN/confirm after the CAS window returns the
// already-settled row rather than double-firing notifications.
async function applyDepositSettlement(io, id, tranId) {
  const settled = await CareRequest.findOneAndUpdate(
    { _id: id, status: 'awaiting_deposit' },
    {
      $set: {
        status: 'deposit_paid_admin_reviewing',
        deposit_amount: DEPOSIT_AMOUNT,
        deposit_transaction_id: tranId,
        deposit_paid_at: new Date(),
      },
    },
    { new: true },
  );
  if (settled) {
    await notifyAdminsBookingReady(io, settled);
  }
  return settled;
}

// Atomically settle the Phase-2 balance: awaiting_final_payment -> approved.
async function applyBalanceSettlement(io, id, tranId) {
  const settled = await CareRequest.findOneAndUpdate(
    { _id: id, status: 'amount_assigned_awaiting_final_payment' },
    {
      $set: {
        status: 'approved',
        final_transaction_id: tranId,
        final_paid_at: new Date(),
        'payment.released_at': new Date(),
      },
    },
    { new: true },
  );
  return settled;
}

// Outstanding balance for a priced request. Never negative.
function outstandingFor(doc) {
  const fee = Number(doc.final_price) || 0;
  const deposit = Number(doc.deposit_amount) || 0;
  const discount = Number(doc.adjusted_discount) || 0;
  return Math.max(0, roundMoney(fee - deposit - discount));
}

// POST /patient/requests/:id/deposit/init — open a ৳100 gateway session.
router.post('/requests/:id/deposit/init', requireAccountId, async (req, res) => {
  try {
    const doc = await loadOwnedRequest(req, res);
    if (!doc) return;
    if (doc.status !== 'awaiting_deposit') {
      return res.status(409).json({
        message: 'This booking is not awaiting a confirmation deposit.',
      });
    }
    const tranId = paymentService.makeTranId('DEP');
    const base = `${PUBLIC_BASE_URL}/patient/requests/${doc._id}/deposit`;
    const session = await paymentService.initSession({
      amount: DEPOSIT_AMOUNT,
      tranId,
      productName: `Booking confirmation deposit — ${doc.care_type}`,
      customer: customerFromRequest(doc),
      successUrl: `${base}/return?result=success`,
      failUrl: `${base}/return?result=fail`,
      cancelUrl: `${base}/return?result=cancel`,
      ipnUrl: `${base}/ipn`,
    });
    res.json({
      amount: DEPOSIT_AMOUNT,
      tranId: session.tranId,
      simulated: session.simulated === true,
      gatewayUrl: session.gatewayUrl || null,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/deposit/confirm — settle after gateway return
// (or immediately, in simulated mode). Body: { tranId, valId? }.
router.post('/requests/:id/deposit/confirm', requireAccountId, async (req, res) => {
  try {
    const doc = await loadOwnedRequest(req, res);
    if (!doc) return;
    const b = req.body || {};
    const tranId = b.tranId || paymentService.makeTranId('DEP');
    const valid = await paymentService.validate({
      valId: b.valId,
      expectedAmount: DEPOSIT_AMOUNT,
    });
    if (!valid) {
      return res.status(402).json({ message: 'Deposit payment could not be verified.' });
    }
    const settled = await applyDepositSettlement(req.app.get('io'), doc._id, tranId);
    if (!settled) {
      // Either already settled (idempotent) or no longer awaiting deposit.
      const fresh = await CareRequest.findById(doc._id);
      if (fresh && fresh.status !== 'awaiting_deposit') return res.json(fresh.toJSON());
      return res.status(409).json({ message: 'Deposit could not be applied.' });
    }
    res.json(settled.toJSON());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/deposit/ipn — SSLCommerz server-to-server IPN.
// Public (the gateway posts here); the val_id is validated before we trust it.
router.post('/requests/:id/deposit/ipn', async (req, res) => {
  try {
    const b = req.body || {};
    const valid = await paymentService.validate({
      valId: b.val_id,
      expectedAmount: DEPOSIT_AMOUNT,
    });
    if (!valid) return res.status(400).json({ message: 'Invalid IPN' });
    await applyDepositSettlement(req.app.get('io'), req.params.id, b.tran_id || b.val_id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/balance/init — open a gateway session for the
// outstanding balance (final fee − deposit − discount).
router.post('/requests/:id/balance/init', requireAccountId, async (req, res) => {
  try {
    const doc = await loadOwnedRequest(req, res);
    if (!doc) return;
    if (doc.status !== 'amount_assigned_awaiting_final_payment') {
      return res.status(409).json({
        message: 'This booking has no outstanding balance to pay.',
      });
    }
    const amount = outstandingFor(doc);
    const tranId = paymentService.makeTranId('BAL');
    if (amount <= 0) {
      // Fully covered by the deposit/discount — settle straight through.
      const settled = await applyBalanceSettlement(req.app.get('io'), doc._id, tranId);
      return res.json({
        amount: 0,
        tranId,
        simulated: true,
        gatewayUrl: null,
        settled: !!settled,
      });
    }
    const base = `${PUBLIC_BASE_URL}/patient/requests/${doc._id}/balance`;
    const session = await paymentService.initSession({
      amount,
      tranId,
      productName: `Balance payment — ${doc.care_type}`,
      customer: customerFromRequest(doc),
      successUrl: `${base}/return?result=success`,
      failUrl: `${base}/return?result=fail`,
      cancelUrl: `${base}/return?result=cancel`,
      ipnUrl: `${base}/ipn`,
    });
    res.json({
      amount,
      tranId: session.tranId,
      simulated: session.simulated === true,
      gatewayUrl: session.gatewayUrl || null,
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/balance/confirm — settle the balance. Body:
// { tranId, valId? }. Advances the request into the dispatch queue.
router.post('/requests/:id/balance/confirm', requireAccountId, async (req, res) => {
  try {
    const doc = await loadOwnedRequest(req, res);
    if (!doc) return;
    const b = req.body || {};
    const tranId = b.tranId || paymentService.makeTranId('BAL');
    const valid = await paymentService.validate({
      valId: b.valId,
      expectedAmount: outstandingFor(doc),
    });
    if (!valid) {
      return res.status(402).json({ message: 'Balance payment could not be verified.' });
    }
    const settled = await applyBalanceSettlement(req.app.get('io'), doc._id, tranId);
    if (!settled) {
      const fresh = await CareRequest.findById(doc._id);
      if (fresh && fresh.status !== 'amount_assigned_awaiting_final_payment') {
        return res.json(fresh.toJSON());
      }
      return res.status(409).json({ message: 'Balance could not be applied.' });
    }
    res.json(settled.toJSON());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// POST /patient/requests/:id/balance/ipn — SSLCommerz server-to-server IPN.
router.post('/requests/:id/balance/ipn', async (req, res) => {
  try {
    const b = req.body || {};
    const doc = await CareRequest.findById(req.params.id);
    if (!doc) return res.status(404).json({ message: 'Request not found' });
    const valid = await paymentService.validate({
      valId: b.val_id,
      expectedAmount: outstandingFor(doc),
    });
    if (!valid) return res.status(400).json({ message: 'Invalid IPN' });
    await applyBalanceSettlement(req.app.get('io'), doc._id, b.tran_id || b.val_id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET /patient/requests/active  — the caller's newest non-terminal request.
//
// Scoped strictly to the authenticated account. `attachAccountId` resolves
// identity from the bearer token (canonical), falling back to the
// `x-account-id` header / `account_id` query for legacy callers. We must
// NEVER run an unscoped query: with no `patient_account_id` filter,
// `findOne` returns the newest active booking of ANY patient, leaking a
// stranger's request into this feed (and then the payment ownership guard
// correctly rejects it with "Not your booking").
router.get('/requests/active', attachAccountId, async (req, res) => {
  try {
    if (!req.accountId) {
      return res.status(404).json({ message: 'No active request' });
    }
    const doc = await CareRequest.findOne({
      status: { $nin: TERMINAL },
      patient_account_id: req.accountId,
    }).sort({ created_at: -1 });
    if (!doc) return res.status(404).json({ message: 'No active request' });
    const body = await attachDoctorToRequest(doc.toJSON());
    res.json(body);
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET /patient/home  — minimal home-feed shape, scoped to the caller.
router.get('/home', attachAccountId, async (req, res) => {
  try {
    // Same rule as /requests/active: only ever the authenticated patient's
    // own active request, never a fallback unscoped cross-patient query.
    const active = req.accountId
      ? await CareRequest.findOne({
          status: { $nin: TERMINAL },
          patient_account_id: req.accountId,
        }).sort({ created_at: -1 })
      : null;
    const activeJson = active
      ? await attachDoctorToRequest(active.toJSON())
      : null;
    res.json({
      active_request: activeJson,
      recent_providers: [],
      unread_notification_count: 0,
      fetched_at: new Date().toISOString(),
    });
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// GET /patient/profile?account_id=
// Returns the Account document for the signed-in patient. Passwords are
// stripped automatically by the Account model's toJSON transform.
router.get('/profile', async (req, res) => {
  try {
    const { account_id } = req.query;
    if (!account_id) {
      return res.status(400).json({ message: 'account_id is required' });
    }
    const acct = await Account.findById(account_id);
    if (!acct) return res.status(404).json({ message: 'Account not found' });
    res.json(acct.toJSON());
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

// PATCH /patient/profile  { account_id, full_name?, email?, phone? }
// Partial update via findByIdAndUpdate so a save touching only `phone`
// does not wipe `email` or `full_name`. Returns the updated document.
router.patch('/profile', async (req, res) => {
  try {
    const body = req.body || {};
    const accountId = body.account_id;
    if (!accountId) {
      return res.status(400).json({ message: 'account_id is required' });
    }
    const updates = pickPatientFields(body);
    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ message: 'No editable fields supplied' });
    }
    const acct = await Account.findByIdAndUpdate(
      accountId,
      { $set: updates },
      { new: true, runValidators: true }
    );
    if (!acct) return res.status(404).json({ message: 'Account not found' });
    res.json(acct.toJSON());
  } catch (err) {
    // Duplicate email surfaces as a Mongo 11000 — translate to 409 so the
    // Flutter side can show a friendly "Email already in use" SnackBar.
    if (err && err.code === 11000) {
      return res.status(409).json({ message: 'Email is already in use' });
    }
    res.status(500).json({ message: err.message });
  }
});

// GET /patient/requests/history
// Closed (terminal) requests, newest first — powers the "View past requests"
// row on the Patient Profile screen. Scoped to the authenticated caller so
// it can't enumerate other patients' history.
router.get('/requests/history', attachAccountId, async (req, res) => {
  try {
    if (!req.accountId) return res.json([]);
    const rows = await CareRequest.find({
      status: { $in: TERMINAL },
      patient_account_id: req.accountId,
    })
      .sort({ created_at: -1 })
      .limit(50);
    res.json(rows.map((d) => d.toJSON()));
  } catch (err) {
    res.status(500).json({ message: err.message });
  }
});

module.exports = router;
