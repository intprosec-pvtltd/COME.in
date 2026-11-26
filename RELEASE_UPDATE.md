# Stay Sync Manage feedback, privacy and app update

This is the complete Mobile Resident Deletion source package plus the changes listed in UPDATE_FILES.txt. Back up or compare the listed files before merging into your staging checkout. All existing database and storage locations are configured separately.

## Feedback and mobile QA

Owners and residents can open Account → Rate Stay Sync Manage. The optional private prompt appears after 10 minutes of foreground use on an eligible signed-in dashboard, then no more often than every 24 hours when dismissed. Feedback submission stops automatic reminders on that device. Ratings are stored per account and tenant. Platform administrators read them in App Feedback. They are not sent to Google Play.

Test profile navigation by tapping the full card. On Edit resident, select the PG, a room with availability, and a free bed. Changing rooms resets the bed choice. Saving other edits can keep a legacy allocation as it was. The backend independently checks a changed assignment. Test Copy UPI ID, the photograph and document preview close buttons, and manual verification controls.

## Configure and verify production

1. Review backend/.env.production.example. Set values through the hosting environment or managed secrets. Use STAYSYNC_ENV=production on production-like staging and production. Use persistent PostgreSQL with the appropriate TLS settings for your host, and explicit durable paths for private uploads, chat uploads, and the separate subscription database and media.
2. Keep distinct stable signing and OTP secrets. Disable demo seed and legacy email registration. Configure a live Twilio sender for your SMS route. Leave local QA OTP mode out of staging and production. Test a real, authorized number from the app through to sign-in. Configure email and Firebase if used, and verify delivery.
3. Have IntProSec approve the privacy and terms text, provider list, retention periods and deletion procedure. Confirm that info@intprosec.com is monitored for privacy requests. The legal/ directory contains three ready-to-review HTML pages. Publish the approved versions at publicly accessible HTTPS URLs and set PRIVACY_POLICY_URL, TERMS_URL and ACCOUNT_DELETION_URL. Update Play Console Data safety to reflect the actual deployment. Verify that account deletion requests are processed and associated data is removed or retained only where applicable.
4. Terminate HTTPS at the configured reverse proxy or hosting edge. Set exact HTTPS storefront dashboard origins in CORS_ORIGINS. Verify storage permissions and restore, tenant access isolation, health, proxy behavior and database migrations on staging. Review the known single-ledger and local-storage deployment constraints before adding API replicas.
5. Build the Android bundle from mobile with an explicit staging or production HTTPS URL:
   `flutter build appbundle --release --dart-define=API_URL=https://YOUR-APPROVED-API-HOST`
   Use your existing signing setup, and verify the signed artifact on a physical phone through the intended release track.

The package contains no live credentials or production configuration values. Evidence in this environment covers source builds and automated tests. No Android APK/AAB or hosted deployment was verified here.
