# COME.in source update V2.2 — scope and validation

## Source additions
- Added private PG-scoped chat uploads: JPEG/PNG/WebP/PDF/TXT, maximum 10 MB, authenticated retrieval API, message history attachment metadata, owner moderation (existing), and filename path sanitization.
- Added Flutter camera / photo / document pickers and a lightweight emoji picker.
- Added authenticated in-app notification feed for new messages from others, notices, and facility incidents. A notifications navigation action is available in both owner and resident Services/Actions.
- Added India-time display helper converting UTC timestamps to UTC+5:30 for user-facing chat and notification times.
- Added branded action feedback with another_flushbar, retained existing forms, analytics, expense API, room management and existing workflows.
- Updated LOGIN test to match the COME.in LoginPage and kept prior 3-file analyzer corrections.

## Does not claim to be complete yet
- Background push: NOT included. Requires FCM, Android notification permission, server event routing and device token security.
- Attachments: upload and authorized download API included; inline authenticated image preview/open-in-app is NOT included. UI currently displays document/photo names rather than rendering images.
- Full UI match with supplied design boards is NOT achieved yet. Several detailed pages still use older V2 generic Card/ListTile layouts. The provided reference boards are design targets, not pixel-perfect implemented screens.
- Android Flutter run could not be verified in this environment because Flutter SDK is absent. Earlier red-screen `_dependents.isEmpty` must be retested with stack traces, not assumed resolved.
- Database: SQLite auto-create works for new dev tables, but production requires Alembic migrations, encrypted object storage, malware scanning, rate limits, upload retention policy, secure audit trail, and automated isolation tests.
- No production-grade notification engine or revenue settlement.

## Apply
This ZIP has one pg_platform_mvp folder. Back up backend and Flutter lib, and preserve existing database and .env. Copy backend/main.py, backend/v2_api.py, backend/requirements.txt; and all mobile/lib and mobile/pubspec.yaml, mobile/test into the existing project. DO NOT replace your generated mobile/android folder.

## Check in Windows PowerShell
cd C:\PG-Platform\pg_platform_mvp\backend
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
& .\.venv\Scripts\python.exe -m py_compile main.py v2_api.py
& .\.venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000

In another terminal:
cd C:\PG-Platform\pg_platform_mvp\mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000

Keep Android emulator closed during the build on low-RAM computers.

## Environment notes
- Local chat files stored in backend/chat_uploads (excluded from this archive); back up this directory when moving environments.
- The `apiBase` Android emulator address 10.0.2.2 is NOT a production URL.
- All demo UI calculations and notices should be tested against actual API data.
