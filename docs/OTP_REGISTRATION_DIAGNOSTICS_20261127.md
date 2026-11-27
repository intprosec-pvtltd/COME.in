# StaySync Manage — registration OTP diagnostic and recovery update

Baseline: Git commit 5339fd4, uploaded complete source archive. This is a targeted source update, not a verified production deployment.

## Findings

- Flutter already awaits `/api/v3/phone/register/request` before showing the OTP form. The account is created only after a successful OTP confirmation.
- Registration intentionally suppresses SMS for a previously bound number. Password recovery intentionally suppresses SMS for ineligible accounts. Both use the same SMS transport and uniform public response.
- The previous transport discarded Twilio's numeric error code and treated any HTTP 2xx as acceptance. Delivery exceptions were logged generically. A successful public OTP request therefore never proves an SMS was sent.
- Twilio trial recipient, sender, geography and custom-content restrictions are a likely provider-side explanation, not a verified root cause for the specific recipient. A different Twilio account in Render or an existing phone binding also remains possible. Current provider references: https://www.twilio.com/docs/usage/trials and https://www.twilio.com/docs/api/errors/21608.

## Changes

- `backend/sms_transport.py`: dependency-free Twilio REST transport. Checks structured response status and error code; records only allowlisted status and numeric error metadata through the caller. Retains the same sender selection, endpoint, body and 15-second timeout. Acceptance is not proof of handset delivery.
- `backend/phone_auth.py`: safe provider rejection logs, purpose-specific accepted/failed/skipped logs; existing public response and challenge invalidation retained. No phone number, OTP, credentials or raw provider payload in new logs. Default Uvicorn INFO logging exposes accepted/skipped events; warning logs expose provider rejection.
- `mobile/lib/features/auth/auth_screens.dart` and `phone_verification.dart`: registration-only missing-SMS guidance and change-number action. No change to password recovery or activation UI.
- `backend/tests/test_sms_transport.py`: 20 offline cases, all passed in the build environment.
- `backend/tests/test_phone_auth_phase2.py`: two additional integration tests for failed delivery and duplicate-number suppression; not run here because `pwdlib` was unavailable and dependency installation failed.
- This document is the update's test and deployment report. The pre-existing RELEASE_MANIFEST.json and historical release documents describe older releases and are preserved, not current QA evidence.

No schema migration, database cleanup, OTP bypass, credentials change, dependency upgrade, production URL change, new SMS provider or unrelated source/UI change. Existing account deletion implementation was reviewed: it includes verified-phone and reset-grant rows among technical cleanup candidates; live behavior has not been verified. Rate limits and separate challenge purposes remain intact.

## Local testing before deployment

Use a clean staging checkout or the existing checkout on a new branch. Keep the local environment, database, signing keys and customer data outside the uploaded ZIP. Do not replace the existing checkout or copy generated files over it. The ZIP contains all original archived files plus the targeted additions. Copy the seven files listed above (including this document) onto the baseline. Compare the Git diff.

From the backend directory with its existing Python virtual environment activated, run `python -m pip install -r requirements-dev.txt`, then `python -m pytest -q tests/test_sms_transport.py` and `python -m pytest -q tests/test_phone_auth_phase2.py`. Run the remaining regression suites in isolated test environments, not against production data. Use the project's existing QA setup for those suites. From mobile run `flutter analyze` and `flutter test`. Flutter/Dart were unavailable in the build environment, so these have not been run. Backend Python compilation passed; no live SMS, PostgreSQL, mobile build or dashboard regression was verified here.

## Production diagnosis after tested backend deployment

1. In Render, confirm the service is using the same Twilio account shown in the console. Compare the Account SID privately; never share Auth Token, OTP secret or live database credentials. Ensure Uvicorn INFO logs are enabled. Keep existing stable secrets and storage settings.
2. Use a genuinely new, authorized test mobile number and verify it as a Twilio trial recipient if applicable. Confirm the sender, country and allowed message content with Twilio. Upgrade and obtain applicable compliance approval if unrestricted commercial SMS is needed. Do not use a fixed OTP or weaken verification to bypass provider restrictions.
3. Request registration OTP once. Review Render logs for `SMS verification request accepted purpose=register`, `SMS verification skipped purpose=register reason=ineligible`, or `SMS verification delivery failed purpose=register` and the corresponding `SMS provider rejected request` line. Provider acceptance must be followed by checking final Twilio Messaging status and actual handset receipt. A generic HTTP 200 is not delivery evidence.
4. If provider code 21608 occurs, resolve verified recipient or compliance profile restrictions in Twilio. If the request is skipped, investigate the existing verified binding via authorized account support; do not delete bindings manually or expose eligibility publicly. If other errors occur, consult the Twilio error dictionary. If a message is accepted but later fails, review Twilio final status. If no event appears, verify deployed commit and service logs.
5. Verify new registration, resend, OTP expiry, wrong code, duplicate number, existing mobile enrollment, Forgot Password and login using dedicated test accounts. Verify approved legal version remains required in production. Only then publish the updated mobile application; backend diagnostics alone do not require an APK rebuild.

## Test evidence

- SMS transport offline tests: 20 passed.
- Backend syntax compilation: passed.
- Phone authentication integration suite: collection blocked by missing `pwdlib`; installation attempt unsuccessful.
- Flutter analysis/tests/APK: not run (SDK unavailable).
- Live provider, production configuration, database and dashboard functionality: not verified.
- No actual deployment performed. Original project files are retained; archive integrity and unchanged-file comparison performed during packaging.
