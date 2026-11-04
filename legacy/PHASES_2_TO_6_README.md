# PG White-Label Platform — Integrated mobile V2 (Phases 1–6 source draft)

## What is included

This archive merges the original uploaded MVP, the Phase 1 files and the new V2 source. The original `web` and `platform-admin` folders remain **unchanged**; the PG owner uses the mobile app instead of needing the owner web UI. The central platform administrator is a separate product role.

### Existing files updated
- `mobile/lib/auth/role_router.dart` — routes owners/managers to `OwnerV2`, residents to `ResidentV2`.
- `backend/main.py` — registers V2 API router while preserving original API routes and tables.
- Phase 1 updated files: `mobile/lib/main.dart`, `mobile/pubspec.yaml`.

### New files
- `backend/v2_api.py` — additive SQLAlchemy tables and authenticated endpoints.
- `mobile/lib/core/v2_ui.dart` — shared API data panels, dialogs and notifications.
- `mobile/lib/owner/owner_v2.dart` — mobile owner dashboard and operations.
- `mobile/lib/resident/resident_v2.dart` — mobile resident dashboard and services.
- `mobile/lib/community/community_screen.dart` — PG community text chat.
- Phase 1 additions in `mobile/lib/auth/` and `mobile/lib/core/`.

### Feature coverage
- Role-directed single Flutter app (owner, manager, resident) and secure token storage.
- Owner: period-specific rent totals, resident-wise paid/pending/partial/unbilled status, invoice creation, payment approval/rejection, receipt view, rooms/beds, resident create/edit, ticket status, outage posts, notices, weekly meal menu, bank/UPI editing (owner only).
- Resident: rent due, invoices, payment reference submission, payment status/receipts, facility incidents, notices, tickets, weekly meals, chat.
- Community: stored group text messages restricted to authenticated users in the same PG; owners/managers can remove messages. The app refreshes messages every four seconds while the chat page is active.

## Installation on user's Windows environment

**Back up your current database and source directory first**. This is an additive update; do not delete or recreate `pg_dev.db`. Extract archive into `C:\PG-Platform\` (archive has root `pg_platform_mvp/`), merging the project. Keep your existing `backend/.env`, local Python `.venv`, generated Flutter `android/` directory, and other environment-specific files. The zip intentionally excludes secrets, database files and generated toolchains.

Backend terminal:
```powershell
cd C:\PG-Platform\pg_platform_mvp\backend
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
& .\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
When the backend first imports the V2 module, SQLAlchemy creates the **new** `pg_rooms`, `pg_facilities`, `pg_chat_messages`, and `pg_meals` tables in the existing configured database. In production, replace automatic `create_all()` with migrations after reviewing schema and data backup.

Flutter terminal (close emulator first to conserve RAM):
```powershell
cd C:\PG-Platform\pg_platform_mvp\mobile
flutter pub get
flutter analyze
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000
```
Start the Android emulator after compiling, install the APK with ADB, keep backend running, then log in using your existing accounts.

## Known gaps and quality gates (do not call this production-ready)

1. **No build/runtime verification in the creation environment**: Flutter SDK was not present. Run `flutter analyze`, `flutter test`, APK build, and physical/emulator tests on the Windows machine. Fix findings before release.
2. **No live push/websockets**: chat is functional *polling* (4-second intervals), not WhatsApp-grade real-time delivery; no attachments, typing status, mute, member management or read receipts.
3. **Payment evidence**: payment reference accepted, but file upload/payment-proof image, actual bank reconciliation, immutable audit trail, downloadable signed PDF receipts and settlement handling are not implemented. Approval is a manual owner action; bank credit must be checked independently.
4. **Room inventory**: no bed assignments, room availability enforcement or occupant exit workflow yet. Room string assignments are legacy model fields.
5. **Operations**: meal schedule provided; staff scheduling, food attendance, deposits, refunds, advanced accounting, broadcast push notifications, and full PG branding are not implemented.
6. **Security**: no production migrations, automated API isolation tests, token refresh/revocation, rate limiting, MFA, chat abuse prevention, audit trails, backup/restore, storage isolation, input content moderation, or rigorous security assessment. Backend default dev secret must never be used in production.
7. **Owner settings**: changing bank details uses the original API and is not step-up authenticated; restrict to trusted owner until stronger controls are built.
8. **UI**: dialogs are functional but basic; form validation is minimal and some items are view-only by design; audit UX, pagination/accessibility, offline handling and empty/loading states before deployment.
9. **Data scope**: original backend permits global unique email across tenants. Tenant segregation is performed on all V2 data operations, but production multi-tenant database architecture needs complete audit.

### Suggested final acceptance tests

- Owner and resident log in to the **same APK**, are routed correctly, and logout removes stored token.
- Owner creates room, resident, invoice; rent aggregates show expected current period values.
- Resident views only their invoices and submits reference; owner checks bank then approves; resident sees paid balance and receipt.
- Resident can raise ticket; owner changes ticket status; owner can create facility notice, announcement and meal menu; resident sees them.
- A second tenant cannot view/edit first tenant's messages, residents, invoices, rooms, payments, or notices; unauthorized API requests reject correctly.
- Cross-tenant requests, missing token, invalid inputs, duplicate submissions, and expired tokens are tested.
- Chat text is shared only among current tenant members; owner can remove messages; old messages remain appropriately scoped.
- Verify Android emulator and physical device networking; production API uses HTTPS and correct network security settings.
