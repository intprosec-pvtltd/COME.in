# Delivery validation — 2 November 2026

## Executed

- Python compilation/import checks: passed.
- FastAPI integration suite: **21 passed**, using isolated temporary SQLite databases.
- Additive migration idempotence and existing-user preservation: passed within the suite.
- Dart grammar parsing: **16 active Dart source/test files, zero parse errors**. A grammar check does not perform type resolution or validate Flutter/plugin APIs.
- Source coverage audit: all 25 original HTML destinations mapped to Flutter implementations; detail/form/recovery/account screens are additionally included.

The backend suite tests login/state authentication; owner/resident permissions; properties and transactional bed allocation conflicts; actual private upload requests and file-byte validation; payment proof, bank-confirmation requirement, approval/rejection, duplicate references, overpayment and receipt access; complaint assignment/history and staff access; facilities/notices/meals/expenses/bookings; chat edit/unsend/delete-for-me, ownership and protected attachment retrieval; profile/preferences; tenant isolation and joining codes; token revocation and password-change invalidation; in-app reminders; phone login; cross-tenant private-file rejection; password-reset code workflow with a mocked email sender. See the JUnit XML and `backend/tests/test_v3.py`.

One test-environment warning concerned FastAPI/Starlette's future test-client transport change. Tests passed. The source requirements retain the project's compatible version ranges; installed versions used for these checks are listed separately.

## Included but not executed

Five Flutter widget/unit tests cover login validation/recovery navigation, owner directory navigation, resident navigation, editor schema coverage and invoice status calculations. Native analyzer, widgets, package resolution, Android build, emulator/device launch, plugin permissions, screenshot comparison and iOS build were not executed. PowerShell scripts were reviewed but not executed in a Windows shell. No APK is included.

Flutter SDK acquisition was blocked by automatic approval review after an unexpected cloud metadata request, which could expose credential material. It was not retried or bypassed. Existing app source and backend testing continued independently. Use your installed Flutter SDK with `scripts/Test-All.ps1`; resolve any analyzer/device findings before release.

## External and production validation

Live SMTP delivery needs your SMTP configuration; only the recovery logic and sender invocation were tested. Background push is not configured. Chat uses five-second foreground polling of the latest 200 messages. Native UI appearance has been implemented against the HTML design but has not been visually verified on a running Flutter app. PostgreSQL behavior and concurrent financial operations require database-specific tests; the integration suite used SQLite. Existing legacy API endpoints remain in place and have not undergone a full production security audit. Terms/privacy need company approval.

Do not treat this package as a certified production release or an error-free native build. The purpose is a consolidated, reviewable source implementation with a clear local verification path.
