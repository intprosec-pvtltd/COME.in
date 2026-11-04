# COME.in Flutter application update

This package implements the supplied plum/lavender COME.in design as a native Flutter/Dart app, using your earlier `pg_platform_mvp(1).zip` project and its FastAPI API as the starting point. It includes the complete mobile application source, the original logo and icon, distinct onboarding artwork, the backend additions, migration, tests and Windows scripts.

**Validation:** 21 backend integration tests passed. All 16 active Dart source/test files passed a Dart grammar syntax check. Flutter dependency resolution, analyzer, widget tests, Android build, emulator launch and iOS build were **not executed** here. Read `docs/TESTING_REPORT.md` before treating this as a verified native release.

## Update your existing Windows project

1. Stop the running backend and mobile app. Extract this package outside `C:\PG-Platform\pg_platform_mvp`.
2. Open PowerShell in the extracted `comein_app` directory.
3. Install the updated source:

```powershell
.\scripts\Install-Update.ps1 -TargetRoot 'C:\PG-Platform\pg_platform_mvp'
cd C:\PG-Platform\pg_platform_mvp
```

The installer backs up replaced source under `comein_code_backup_<timestamp>`. It preserves `.env`, databases, virtual environments and existing Android/iOS build files. The source backup is not a substitute for a database backup.

4. Start the API:

```powershell
.\scripts\Run-Backend.ps1
```

The script uses Python 3.11, creates a backend `.venv` only if missing, installs dependencies, backs up the default local SQLite file and runs the additive V3 migration. If your `.env` points to PostgreSQL or a different SQLite path, back up that database separately first.

5. In another PowerShell window, start the Flutter app:

```powershell
cd C:\PG-Platform\pg_platform_mvp
.\scripts\Run-Mobile.ps1 -ApiUrl 'http://10.0.2.2:8000'
```

`10.0.2.2` is for the Android emulator. For a physical Android device, use the development computer's LAN address, keep both devices on the same network and permit the API port in the firewall. Release builds must use the configured HTTPS API address.

`Initialize-Mobile.ps1` retains existing native platform directories. If one is absent, it generates that directory in a temporary Flutter project using your installed SDK and copies only the missing native directory. It does not replace your app's Dart code with Flutter starter code. It adds camera/network declarations and iOS privacy descriptions, permits local HTTP in Android **debug** only, resolves packages and generates the launcher icons from your supplied image.

## Fresh installation

You can also run the extracted project directly:

```powershell
.\scripts\Run-Backend.ps1 -Demo
```

In another window:

```powershell
.\scripts\Run-Mobile.ps1
```

`-Demo` enables seed accounts only when creating a new `.env` and an empty database. Existing `.env` settings are retained. Seed accounts use `owner@demo.pg`, `resident@demo.pg` and `staff@demo.pg`; the password is `Demo123!`. Disable demo seeding for a real installation. Without demo seeding, create your owner account from the app. Owners can obtain a joining code under Manage for residents to self-register.

The existing backend also accepts PostgreSQL via `DATABASE_URL`, for example `postgresql+psycopg://...`. Supply your actual credentials in your existing `.env`; no hosted account or AWS service is required by this source.

## Run the native checks on your computer

Use your existing Flutter setup (reported as Flutter 3.44.4). This source uses recent Flutter Material 3 APIs and requires a modern SDK; the minimum Dart language constraint is 3.8.

```powershell
.\scripts\Test-All.ps1
```

This runs `flutter analyze`, `flutter test`, an Android debug APK build and the backend tests. The app's API URL is supplied with `--dart-define=API_URL=...`. The Flutter widget/unit tests are included but were not run in the delivery environment.

For iOS, use a Mac with Xcode, configure signing and validate camera/gallery, secure storage and device networking separately. Windows cannot produce a signed iOS build. Keep your existing package identifiers/signing configuration when updating an installed app.

## Included pages and connected workflows

- Splash; three swipeable onboarding pages; sign-in; registration; forgot/reset password.
- Owner and resident dashboards; role-specific navigation; management/explore directory.
- Property directory, details, editing and guarded archive; property filters.
- Rooms by floor, bed map, room details and transactional resident bed allocation.
- Resident directory, search, details, editing and in-app rent reminders.
- Rent/invoices, paid/pending/partial/overdue filters, invoice creation, owner payment details.
- Payment proof selection/upload, owner verification, rejection reasons, approved receipts and receipt saving.
- Expense ledger, expense editing, reports, occupancy, CSV saving and real ledger totals.
- Complaints, camera/gallery photos, priority, staff assignment, progress and resolution history.
- Facility updates with status history; announcements with read/archive states; weekly food menus.
- Staff directory, staff details and assignments; staff login for assigned maintenance tasks.
- Booking enquiries and status changes, without inventing reservation payment rules.
- Private community chat, text/media, authenticated image preview and file saving, reply/copy/edit/unsend/delete-for-me, IST times, refresh and lifecycle-aware polling.
- In-app notifications, read state, notification preferences, light/dark/system appearance.
- Account/profile, password changes, accommodation, joining code, help, legal-review page and logout.

`docs/SCREEN_COVERAGE.csv` maps every original HTML destination to its Flutter implementation and API. Original mobile sources are retained under `legacy/mobile_lib` for reference; they are not compiled into the new app. Existing React owner-web and platform-admin source directories are retained.

## Configuration and limits

- Password recovery code delivery is implemented through STARTTLS SMTP. Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, and, when required, `SMTP_USER`/`SMTP_PASSWORD` in `.env`. Without a configured provider, the app shows the backend's configuration error; it does not claim an email was sent. SMTP delivery was tested with a mocked sender, not a live provider.
- In-app notifications work through the API. Background push credentials, dispatch and delivery are not configured in this package.
- Chat uses a full reconciliation of the latest 200 messages every five seconds while foregrounded. It is not WebSocket-based; older-message pagination remains a scalability follow-up. Delete-for-me is stored server-side per user. Edit/unsend is limited to 15 minutes server-side.
- Payment approval records the owner's confirmation. The application does not query a bank or transfer funds. Receipts and CSV reports can be saved using the native file picker.
- File storage uses authenticated local server directories. Deployments must persist/back up those directories alongside the database.
- Terms/privacy text requires company review and publication. No AI automation module is added.
- The API tests used temporary SQLite databases. PostgreSQL runtime/concurrency, native plugin behavior, actual device layouts and live SMTP delivery remain unverified. This is source delivery, not a claim of production readiness or an error-free device build.

See `docs/MIGRATION_AND_ROLLBACK.md` and `docs/MANUAL_ACCEPTANCE.md` for the remaining verification steps.
