# Device and integration acceptance

These checks remain for the Windows/Android installation and a separate Mac/iOS environment.

1. Run `scripts/Test-All.ps1`. Record Flutter SDK/package versions, analyzer output, widget tests and APK build output. Launch the APK on the configured emulator. Test a narrow device with large text and the keyboard visible; verify back navigation, scrolling and safe areas.
2. Verify the official launcher icon, splash, logo, three distinct onboarding pages, Next/Back/Skip/swipe and onboarding persistence. Confirm sign-in artwork includes both genders and the IntProSec attribution is visible.
3. Log in as owner/resident/staff. Restart the app with remember enabled/disabled. Confirm expired sessions and server disconnection produce recoverable feedback. Change a password; verify other old sessions are rejected. Log out and sign in again.
4. Create/edit a property and room. Add residents and assign/move beds. Try occupied beds and reducing occupied capacity. Verify archive safeguards and property/report filters.
5. Create a current-month invoice. Submit a partial payment with an actual image/PDF from the resident device. Reject it with a reason; correct/re-submit. Approve after independently confirming bank credit. Verify balances, notification, receipt and saved file. Try duplicate references and overpayment.
6. Create/edit an expense. Compare reports and exported CSV with actual database totals. Confirm no dashboard invents historical figures.
7. Report a complaint with a device camera photo. Assign staff, update progress and resolve with notes. Confirm resident history and staff access restrictions. Test a denied camera permission and a cancelled picker.
8. Publish and edit a facility outage; resolve it and inspect status history. Publish/edit/archive an announcement and inspect resident visibility/read state. Set/view menus for multiple weekdays.
9. On two logged-in devices in the same PG, test chat send, emoji, camera/gallery/document upload, thumbnail, full image preview and saved download. Test reply, edit, unsend and delete-for-me; verify changes reconcile on the other device. Test the 15-minute window and sender ownership. Background/resume the app and interrupt the network during send/upload.
10. Use a second PG account to verify the API cannot expose another PG's data or attachments. Confirm native file access is denied after logout.
11. Create staff and enquiry records, update enquiry status, review assignments, edit profile, switch appearance, update notification preferences and mark notifications read.
12. Configure SMTP, then test a real delivered recovery code, invalid/expired code and reuse. Configure and test background push separately if required for the release.
13. On a Mac, validate iOS signing, icons, photo/camera permissions, secure storage, file saving, app lifecycle and networking. Review terms/privacy and production server configuration before customer release.
