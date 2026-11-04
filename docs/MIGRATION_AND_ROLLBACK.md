# Migration and rollback

Before installation, stop the API and back up the entire database and private upload folders. Use a database-native backup for PostgreSQL. `Run-Backend.ps1` automatically copies only `backend/pg_dev.db` when that default file exists; other database locations require your own backup.

The V3 migration creates `comein_v3_documents`, `comein_v3_files` and `comein_v3_alerts` using SQLAlchemy metadata. No existing table or column is dropped. JSON documents hold additive property/bed metadata, histories, preferences, message deletion/read state and audit entries. Legacy residents without new metadata are mapped to rooms in the primary property; existing V3 assignments are preserved. If legacy occupancy exceeds an existing room capacity, unresolved bed numbers stay zero and need owner review. Migration is idempotent and tested for retaining existing users.

Existing tenants, users, invoices, payments, tickets, notices, rooms, facilities, messages, media and expense tables continue to be used. New operations create normal persisted records in these tables. Password changes invalidate prior JWTs and logout records token revocation. Pre-update JWTs remain accepted until expiry unless the user changes their password.

For rollback, stop the API, restore the source backup and restore the complete pre-upgrade database plus associated uploads. Restore source and database together. Do not blindly drop V3 tables: doing so discards allocations, histories, preferences, file metadata and security records. Keep the new database backup if you need to preserve post-upgrade financial or resident changes for reconciliation.

The installer does not overwrite your `.env`, database, virtual environment or existing native project. Copying files manually does not create a backup. No real resident or payment data is included in this package.
