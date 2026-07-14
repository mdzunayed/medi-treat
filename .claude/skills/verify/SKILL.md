---
name: verify
description: Build, launch, and drive the Taafi (medi-treat) Flutter app end-to-end on this machine to verify frontend changes with screenshots.
---

# Verify Taafi frontend changes

Full-stack local run: Node/Express backend on :5000 (local mongod on 27017 is
already active as a systemd service) + Flutter web build served statically +
headless Chrome driven over raw CDP.

## Backend

```bash
cd backend
npm run seed          # idempotent; logs inserted=0 on re-runs
npm start             # port 5000 (from backend/.env), needs local mongod
```

Seeded logins (password for all: `password`):
- patient: phone `8801700000003` (patient@taafi.app)
- doctor:  phone `8801700000001`, admin/support: `8801700000002`

## Frontend

`flutter run -d web-server` fails with exit 255 in a non-TTY background shell —
use a static build instead:

```bash
cd frontend
flutter build web                       # ~1-2 min
cd build/web && python3 -m http.server 8087 --bind 127.0.0.1
```

Frontend default API base URL is `http://localhost:5000` (dio_client.dart), so
no --dart-define needed locally. `flutter build apk` is blocked until Android
NDK licenses are accepted; web is the verification path.

## Driving headless Chrome

No Playwright/Puppeteer installed. Launch Chrome with CDP and drive it with a
step-list runner that talks raw CDP over `ws` from backend/node_modules
(see scratchpad `cdp.js` pattern — steps: navigate/resize/click/type/key/
scroll/screenshot, JSON command files):

```bash
google-chrome --headless=new --remote-debugging-port=9222 \
  --user-data-dir=/tmp/profile --window-size=430,900 --no-first-run about:blank
```

The app renders to canvas (no DOM), so drive it by coordinates: screenshot,
read the image, click at estimated pixels, screenshot again to confirm. Wait
~9s after first navigate for the Flutter bundle to boot.

## Flow gotchas

- After patient login an **app-open ad interstitial** shows (~3s countdown);
  wait it out, then a click in the top-right area dismisses/passes through to
  the header avatar.
- Dark-mode toggle lives on the patient **Account screen** (tap the header
  avatar), Preferences section — not /settings.
- Bottom capsule nav at 430×900: home ≈(159,848), new-request "+" ≈(215,848),
  activities ≈(271,848). Header avatar ≈(398,29) (home screen only).
- The "New care request" header has no avatar; its back arrow (28,28) goes home.
- Care Services layout: carousel <700px window width, 2-col grid ≥700,
  3-col ≥1000 (resize via Emulation.setDeviceMetricsOverride).
