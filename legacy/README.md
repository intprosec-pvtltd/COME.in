# PG White-Label Platform — MVP Foundation v0.1

**Development authorized October 30, 2026.** POCO-yellow/charcoal UI, white-label tenant-scoped backend. This is a **development MVP**, not a production-ready service.

## Included

- `backend/`: FastAPI + SQLAlchemy; PostgreSQL-capable with SQLite local demo mode. JWT authentication, tenant-scoped notices, complaint tickets, monthly rent invoices, resident payment submissions, owner verification and balances.
- `web/`: React JSX/Vite **PG Owner dashboard**: login, overview, residents, publish notices, complaints, invoice creation, payment review and payment account settings.
- `mobile/`: Flutter/Dart **resident mobile starter**: login, notices, complaint submission, invoice and manual payment proof submission, profile.

## Run backend (Windows PowerShell)

```powershell
cd backend
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python -m uvicorn main:app --reload --port 8000
```

Visit http://localhost:8000/docs. Demo seed is enabled in `.env.example` **for local development only**.

## Run owner web dashboard

```powershell
cd web
npm install
Copy-Item .env.example .env
npm run dev
```

Open http://localhost:5173. Demo: `owner@demo.pg` / `Demo123!`.

## Run Flutter Android app

Flutter SDK is required. From `mobile/` execute:

```powershell
flutter create --platforms=android,ios .
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000
```

For a physical phone, use the computer's reachable LAN IP instead of `10.0.2.2`. Development-only HTTP requires Android emulator/manifest cleartext configuration; deploy with HTTPS. On iOS, use Mac/Xcode and HTTPS or appropriate development transport exception. Demo resident: `resident@demo.pg` / `Demo123!`.

## Incomplete / before any production deployment

- Central platform admin panel with **independent platform-admin authentication** (not implemented yet).
- Distinct branded Android/iOS releases and automated app configuration/build pipeline.
- Real QR image uploading and secure document/media storage; bank QR URL field is a placeholder configuration only.
- Resident onboarding, rooms/beds, deposits, food, housekeeping, staff workflow and all remaining approved modules A–P.
- Production hardening: migrations, authorization matrix tests, tenant isolation tests, refresh sessions, password reset/MFA, step-up bank detail changes, immutable financial audit logs, idempotent atomic payment processing, invoice dispute/refund workflows, monitoring, backups, CSRF/CORS review, media security, TLS, and secrets management.
- FCM push delivery, proof image upload and downloadable PDF receipts are **not implemented**.
- Payment gateway automation **not included**; a submitted UPI reference is never trusted as settlement.

**Never use the demo `.env` secret, demo password or `DEMO_SEED=true` in production.**

## Platform Admin React JSX UI (static preview)

```powershell
cd platform-admin
npm install
npm run dev
```

Visit http://localhost:5174. This is a **nonfunctional UI preview**, not an authenticated admin service. No privileged administrative API or data access is present.
