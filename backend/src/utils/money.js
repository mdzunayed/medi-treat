// Currency helpers. All billing amounts are BDT stored as plain Numbers,
// so every computed value must pass through roundMoney() before it is
// stored, compared, or returned — raw float arithmetic (e.g.
// 1000.1 - 100 - 0.2) otherwise leaks binary-fraction error into
// balances the patient is actually charged.

// Fixed slot-confirmation deposit charged in Phase 1. Deducted from the
// final bill. Single source of truth for the whole flow (patient routes,
// admin set-price validation, notification copy).
const DEPOSIT_AMOUNT = 100;

// Round a currency value to 2 decimals. Non-finite input (NaN from a bad
// cast, Infinity) normalizes to 0 so a malformed field can never poison a
// stored balance. Number.EPSILON nudges half-way cases (e.g. 1.005) that
// binary floats represent just under the true value.
function roundMoney(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

module.exports = { DEPOSIT_AMOUNT, roundMoney };
