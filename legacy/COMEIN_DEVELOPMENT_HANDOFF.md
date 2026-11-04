# COME.in — Flutter + FastAPI implementation handoff

## Source and update scope

This project is a **full cumulative source package**, not merely a patch. It contains the original V2 Flutter owner/resident workflows and FastAPI APIs together with the COME.in design implementation. Existing Flutter Android/iOS native folders generated on your Windows machine are **not contained** in the earlier uploaded source ZIP, so **preserve your current `mobile/android` and `mobile/ios` folders** when applying this update.

### Delivered user experience

- COME.in identity using deep plum `#3B1E3F`, lavender `#B794F6`, blush `#F4D7CC`, and off-white `#FAF8F6`.
- Animated opening flow with **four illustrated travelers** (two men and two women), luggage and backpacks, walking forward toward a city PG building, and a PG · STAY sign above the building. Animation built in Flutter with `CustomPainter` and an `AnimationController`, so no network images are required.
- Restyled sign-in and common controls. This uses **existing verified email/password login**. It does not claim OTP signup exists. The PG owner must provision resident accounts through the existing app.
- Separate role-based owner/resident dashboards, preserving existing working APIs and action flows.
- Owner: rent collection, partial/pending dues, room/resident management, payment verification, operations, community, and a Reports tab.
- Resident: rent balance, bill/payment workflow, facilities/outages, notices, complaints, food, and community.
- Reporting: new tenant-isolated `comein_expenses` table, `GET /api/reports/analytics?period=YYYY-MM`, and `POST /api/reports/expenses`. The report computes month-scoped billed/collected/unpaid rent, recorded spending, net cash flow, occupancy, and payment status breakdown.
- Original V2 endpoints remain in place for backward compatibility.

## Critical implementation limitations

1. **Flutter tooling is not installed in this authoring environment.** The Dart code has not been compiled here. Run `flutter pub get`, `flutter analyze`, `flutter test`, then a debug APK build on your Windows development machine. Correct any analyzer/build errors before app testing.
2. Backend Python files passed `py_compile`; a route/tables smoke check was performed with a temporary `pwdlib` stand-in due to unavailable dependency installation. **This is not a real authentication/API test**.
3. The actual COME.in identity artwork was supplied as a composite brand-board image, not a standalone transparent icon. Flutter currently draws a clean doorway-symbol placeholder matching its palette. Replace the placeholder with approved final vector/PNG assets when available.
4. Financial calculation is **net cash flow**, NOT accounting profit; deposits, taxes, accrued liabilities, refunds, GST and balances may not be included. Expense values are owner-entered. Do not present this as audited accounts.
5. Community chat remains text-only and uses 4-second polling; no push notifications or production WebSocket infrastructure is included.
6. This MVP continues using the existing development database and role model. Full production release still requires database migrations, tenant-isolation tests, upload proof validation, audited payment approval, rate limiting, infrastructure hardening, and security review.
7. The browser reference is an interactive **design artifact**, not the compiled Flutter UI. Flutter screens are implemented around the approved palette and key layouts, but not a pixel-perfect screen-by-screen reproduction of every HTML interaction.

## Safe update procedure (PowerShell 5.1)

```powershell
$project = 'C:\PG-Platform\pg_platform_mvp'
$backup  = 'C:\PG-Platform\backups\before_comein_20261031'
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item "$project\backend" "$backup\backend" -Recurse -Force
Copy-Item "$project\mobile\lib" "$backup\lib" -Recurse -Force
Copy-Item "$project\mobile\pubspec.yaml" "$backup\pubspec.yaml" -Force
```

Extract the ZIP to a separate temporary folder, then copy **backend/main.py**, **backend/v2_api.py**, **backend/requirements.txt**, **mobile/lib/** and **mobile/pubspec.yaml** into the existing project. Do not replace your database or `.env`. Leave `mobile/android`, `mobile/ios`, `.venv`, and your secure keystore unchanged.

```powershell
cd 'C:\PG-Platform\pg_platform_mvp\backend'
& '.\.venv\Scripts\python.exe' -m pip install -r requirements.txt
& '.\.venv\Scripts\python.exe' -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

In a second terminal:

```powershell
cd 'C:\PG-Platform\pg_platform_mvp\mobile'
flutter pub get
flutter analyze
flutter test
# Build with emulator closed to reduce RAM usage:
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2:8000
```

Backend health: `http://127.0.0.1:8000/api/health`  
Owner login: `owner@demo.pg` / `Demo123!` (seed demo only)  
Resident login: `resident@demo.pg` / `Demo123!` (seed demo only)  
Never use demo credentials or `DEMO_SEED=true` in production.

## Test checklist

- Confirm animated onboarding, skip, next, and login after fresh install.
- Sign in as owner, verify dashboard and add an expense; revisit report to confirm it updates.
- Change report month and verify figures follow that month.
- Verify owner-only report and expense endpoints return HTTP 403 for a resident token.
- Verify owner never sees another PG tenant's invoices or expenses.
- Verify owner payment approval only after confirming actual bank credit.
- Sign in as resident; check rent, notices, facilities and complaints.
- Send one community message from each role and verify tenant isolation.
- Check offline states, invalid credentials, empty billing month, long text and mobile layouts.
