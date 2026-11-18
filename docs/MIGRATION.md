# Setup and migration plan

**Version:** 1.1 · 17 November 2026 (Asia/Jakarta)\
**Status:** Ordered preparation/cutover guide; no deployment, account access, or historical import has been performed.

Related: [PRD](PRD.md), [TSD](TSD.md), [SDD](SDD.md). The [backend guide](../cloudflare/README.md) is authoritative for exact commands, bindings, variables, bootstrap and cleanup behavior. This guide defines ordering and data safety, not account-specific deployment values.

## 1. Establish ownership and policy

1. Name the business owner and authorized operator for Cloudflare, old Apps Script/image accounts, backups and releases. Confirm the explicit single-business MVP assumption. Do not point another business at the same D1 database.
2. Agree business timezone, overnight/correction handling, bon ceiling/approval/disbursement/repayment procedures, employee disclosure, photo retention, support and backup/restore responsibilities. Alternating check-in/out allows midnight crossings; no schedules or daily quota are implied.
3. Inventory existing records/photos with authorized access. Preserve source exports, schema meaning, original timestamps/identifiers and checksums in a controlled archive before any change. No historical storage format, photo ownership, password scheme or debt state is established by this implementation.
4. Assess exposed legacy credentials and arrange authorized rotation/revocation. Redact remaining backup key material without treating redaction as rotation. Never copy private values or deployment identifiers into examples or source.

## 2. Prepare isolated infrastructure

1. Follow the [backend guide](../cloudflare/README.md) to install dependencies and prepare an isolated local/test environment. Review the Worker/schema version together with the mobile API contract.
2. Create/configure the intended D1 database and private R2 bucket in the authorized account when deployment is authorized. Use the documented binding names; apply migrations to the correct environment only. Verify the actual target before remote migration or seeding. Keep public R2/custom-domain/r2.dev access disabled.
3. Set the documented timezone, session TTL, bon limit and retention explicitly. Default retention disabled means photos accumulate; enabling retention later can delete old evidence. Choose policy before enabling the scheduled deletion path.
4. Bootstrap the first owner using the documented operator-only path and a strong unique password; no public signup, shared demo owner, hard-coded seed password or copied legacy plaintext password. Deliver credentials privately. Create only disposable employee accounts in tests.
5. Configure quota/billing alerts and measure the intended plan. Workers Free 10 ms CPU may not support the selected KDF; retain secure hashing and select a suitable auth/paid plan if needed. R2 allowances can incur billed overage. Verify backup export and a restore exercise before accepting real records.

## 3. Integrate and verify the installed mobile app

1. Finish local Flutter/plugin setup. The isolated toolchain is Flutter 3.32.8 / Dart 3.8.1; dependency resolution completed but Windows plugin symlink setup currently requires Developer Mode. Final local analyzer and all 33 Flutter tests passed after durable recovery integration; backend rerun passed 13 tests including Miniflare, Wrangler dry-run and local D1 migration. Preserve that evidence while resolving the remaining device/release blockers.
2. Build the client with the intended **HTTPS** `API_BASE_URL` and no secret credentials. A missing endpoint must display configuration failure; there is no fake data or Apps Script/Imgur fallback. Native app access does not require replacing the product with a web/PWA.
3. In disposable staging data, run the [TSD verification plan](TSD.md#7-verification-and-release-limits): owner/employee authorization, active/reset/logout, alternating overnight attendance/selfie/private access, bon with no photo, all lifecycle actions, partial/overpayment and concurrent actions, idempotent replay and lost-response recovery. Check the client/server receipt field and pagination metadata agree.
4. Verify real Android/iOS camera permissions, interruption/retake/recovery, keyboard/large text, poor network and restart behavior. Test signing and release builds for each intended platform. Local unit/widget/analyzer success does not qualify camera behavior or distribution.

## 4. Decide historical-data treatment separately

Fresh start and historical import are separate operational choices. Preserve the old archive even if the new system starts empty. Obtain a reconciled mapping from legacy person names to new stable employee IDs; do not merge people by display name alone. New accounts/passwords require explicit provisioning/reset rather than assumed compatibility.

**Never infer historical debt states.** An old bon amount, date, image, or success marker cannot prove approval, disbursement, partial repayment, remaining debt or settlement. Owner/finance must reconcile each imported obligation with evidence, opening balance and audit provenance. Ambiguous rows stay in the archive/reconciliation queue; do not label them `pending`, `disbursed`, or `repaid` just to fit the new schema.

Likewise, an old attendance row without kind cannot be guessed into check-in/out pairs; a device-local timestamp with unknown zone cannot silently become a server UTC event. Do not replay old records through live create endpoints, which would create new times and potentially false debts. Any import requires a separately reviewed importer/schema strategy, dry run, counts/totals/photo-access reconciliation and rollback plan. No importer is delivered here.

Legacy photos may already be public. Making a new R2 bucket private does not remove external copies. Verify retention/ownership and authorized transfer/access before retiring any old photo provider; never delete original evidence merely because a new row exists. Bon in the new system has no photo, but old bon photos may still be subject to archival policy.

## 5. Cut over only after readiness evidence

1. Agree an exact cutover window/timezone and rollback owner. Freeze old writes or define a controlled reconciliation window so there is one authoritative writer per record/event. Capture a final authorized export and outstanding-balance reconciliation.
2. Confirm new owner access, correct business environment, private photos, policy settings, mobile endpoint, backups and plan/CPU feasibility. Use the completed release/device evidence to select the rollout scope.
3. Distribute the qualified installed app through the chosen authorized channel. Explain new credentials, selfie-only attendance, bon without photos, lifecycle meanings, and how to report an uncertain submission.
4. Smoke-check authorized real flows only within the agreed rollout scope, then compare receipts, employee access, open work sessions, outstanding amounts, audit entries and photo availability. Watch quota/CPU/error/storage trends. Do not manufacture demo balances to fill an empty dashboard.
5. Keep the old system read-only and the archive available until reconciliation and retention obligations are complete. Retire old credentials/endpoints only through the authorized operator.

## 6. Failure and rollback

If a response is lost or its typed receipt is malformed, retain the durable pending envelope. After restart, sign in to the same API/user and use Home recovery to resend the unchanged operation/key/photo. One pending operation blocks conflicting writes; do not edit its draft or owner action values to bypass recovery. No tokens/passwords are persisted. If recovery storage is missing or cannot be resolved, inspect authoritative history/audit before another money event. Account creation still requires reloading/checking username after an ambiguous save.

If cutover must stop, pause new writes and preserve D1/R2 data, receipts and audit before routing users elsewhere. Reconcile every event accepted after the final legacy export. Do not delete new records, reset debt status, blindly restore an old database, or run two writable systems to mask discrepancies. A rollback changes the access path; it does not undo already disbursed money or employee attendance.

This document is preparation only. Actual account access, deployment, import, release signing and rollout need their own authorized execution and evidence.
