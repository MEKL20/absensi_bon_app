# Product Requirements Document (PRD)

> Proposed evolution: [customer-owned deployment (BYOC)](BYOC.md). Each business would own its environment; automatic provisioning, workspace pairing and customer updates are not implemented.

**Product:** Absensi & Bon Karyawan\
**Version:** 1.1 · 17 November 2026 (Asia/Jakarta)\
**Status:** Confirmed MVP requirements and implementation contract; release qualification pending.

Related: [documentation guide](README.md), [TSD](TSD.md), [SDD](SDD.md), [migration plan](MIGRATION.md).

## 1. Product and evidence boundary

Deliver a full, installed **Flutter mobile app for Android/iOS** for an owner and employees. The owner manages employee accounts, reviews attendance, and controls cash advances (bon). Employees record check-in/check-out with a selfie and request bon **without any photo**. A selfie is evidence for owner review; it does not establish face recognition, liveness, location, or physical presence.

Version 1.0 reconstructed the old client. Its Apps Script/Imgur integration is a **prior baseline being replaced**, not the current product contract. Version 1.1 describes the implementation in the [Flutter source](../lib/main.dart), [API client](../lib/api_client.dart), and [Cloudflare Worker](../cloudflare/src/index.js). Source presence is not proof of successful execution or deployment.

**Explicit MVP assumption:** one business per backend deployment, with owner and employee roles. There is no tenant selection or isolation model for multiple businesses in one database. No live deployment, account access, historical import, or Android/iOS release qualification is included in this implementation task.

## 2. Roles and scope

| Actor | Allowed actions |
| --- | --- |
| Owner | View business dashboard, list/create/edit employees, activate/deactivate access, reset passwords, review employee attendance/photos and bon, approve/reject/disburse bon, record repayments. |
| Employee | Sign in, view own dashboard/history, submit own attendance with selfie, request own bon and see status/outstanding balance. |
| Maintainer | Configure and operate Workers, D1, private R2, backups, retention, and release packaging through authorized operational access. |

Employee CRUD uses deactivation as removal from active use; historical attendance and financial records remain linked to the employee ID. An owner cannot grant owner privileges through the employee editor. Usernames are fixed after creation in the MVP. Password reset and account activation changes invalidate employee sessions. There is no public registration or employee self-service password recovery.

Excluded from this MVP: web/PWA and desktop products, payroll deduction automation, bank transfers, schedules/lateness/overtime calculations, leave, GPS/geofencing, biometrics, offline submission, persistent sign-in, notifications, and historical migration automation. Disbursement and repayment actions record an owner-confirmed external event; the app does not move money.

## 3. Functional requirements

Stable IDs are retained from v1.0; FR-03 now applies only to attendance, and FR-05 explicitly excludes photos. P0 means required before operational use; P1 means required for a useful first release.

| ID | Priority | Requirement and acceptance criteria |
| --- | --- | --- |
| FR-01 | P0 | Authenticate owner/employee with POST credentials over normal HTTPS. Return server identity and opaque bearer session held only in app memory. Reject invalid/inactive accounts. Logout revokes the session; process restart requires sign-in. |
| FR-02 | P1 | Role-specific dashboard/navigation uses real server data. Owner manages employee create/read/update/active/reset operations; employees see only their own data. Empty/error states must not substitute demo records or invented totals. |
| FR-03 | P0 | Attendance only: capture a camera selfie, prefer front camera, preview/retake it, handle cancellation/permission errors, and require photo before sending. Bon has no camera/photo control or field. |
| FR-04 | P0 | Employee submits `check_in` or `check_out`; server derives employee ID, record ID, and receipt time. Enforce alternating events, including check-out after midnight; reject consecutive same-kind events. No schedule or one-pair-per-calendar-day policy is implied. Show a confirmed receipt/history entry only after server acceptance. |
| FR-05 | P0 | Employee requests bon with positive integer IDR amount within configured ceiling and optional note up to 500 characters; **no photo**. New bon is `pending`. Owner may approve/reject pending requests, disburse approved requests, and record partial/full repayment of disbursed funds. Only full repayment produces `repaid`; overpayment and invalid transitions fail. |
| FR-06 | P0 | Distinguish validation, camera, authorization, rejection, connection, timeout, and uncertain submission outcomes. Persist the pending request/key and attendance photo bytes before send in app-private storage, scoped to API + user. Restore after sign-in/restart; block conflicting writes and lock draft/action values until resolved. Failed or malformed acknowledgement remains uncertain. |
| FR-07 | P0 | Attendance photos remain private in R2 and are served only through authorized Worker requests to owner/the submitting employee. Explain photo use, select retention, and reconcile orphan cleanup without deleting accepted evidence after an uncertain write. No financial record requires an image. |

## 4. User journeys

1. **Sign in:** enter username/password; server returns role and stable user ID. Missing API configuration shows a setup message, never a working demo. Credentials stay out of URLs/logs. Password bytes are not silently trimmed.
2. **Manage employees:** owner creates an employee account, edits name, resets password, or changes active state. Deactivation stops access while preserving history. An ambiguous save requires reloading before retrying account creation.
3. **Attendance:** employee chooses check-in/out, takes a selfie, reviews it, sends, and receives server ID/time. Owner reviews records and opens private photos. Failure retains the draft.
4. **Bon:** employee enters amount and optional note, sends without photo, and sees `pending`. Owner records approve/reject, then disburse, then one or more repayments. Employee history distinguishes requests from actual outstanding debt.
5. **Logout/restart:** successful logout returns to login; tokens/passwords are never persisted. After sign-in, restore the same API/user’s pending operation and show a recovery banner to retry its unchanged payload/key. An expired or revoked token must not permit further server reads/writes.

## 5. Financial and attendance invariants

Bon flow: `pending → approved → disbursed → repaid`, or `pending → rejected`. Partial repayment leaves status `disbursed`; outstanding is `amount - repaidAmount` only while disbursed. Pending, approved, and rejected entries contribute zero to outstanding debt. Every financial transition records actor, server time, and repayment amount in the audit trail. No automatic reversal/reopen/delete workflow is defined.

Attendance is an ordered event stream, independent of calendar-day quotas. Server UTC timestamps are canonical. The configured business timezone is for reporting/date interpretation and must be explicitly agreed before cutover. Shift correction, forgotten check-out, and overnight reporting policies still require an operational decision; do not synthesize missing events.

## 6. Nonfunctional requirements

| ID | Priority | Requirement / acceptance gate |
| --- | --- | --- |
| NFR-01 | P0 | Normal TLS; every protected endpoint checks bearer session, active account, role, and record ownership. No private provider key ships in the app. Password hashing must retain its security work factor even if Free CPU is insufficient. |
| NFR-02 | P0 | Durable server receipts and idempotent attendance/bon mutations; replay of the same key/payload returns the same result, a changed payload conflicts, concurrent financial transitions cannot overpay or duplicate money events. |
| NFR-03 | P0 | Private photos, redacted logs, approved retention/deletion policy, and tested backup/restore for personal and financial records. |
| NFR-04 | P0 | Reproducible selected Flutter/Dart dependencies, analyzer/tests, then release builds/signing and real-device camera qualification for each released platform. Local static/test checks alone do not qualify Android/iOS distribution. |
| NFR-05 | P1 | Indonesian mobile UI supports keyboard, large text, readable status labels, touch targets, long names, loading/empty/error states, and camera recovery. |
| NFR-06 | P1 | Bounded network operations, safe error codes/request identifiers, quota/CPU/storage monitoring, and documented uncertain-write recovery. Free-tier use is an objective, not a guarantee of zero cost or availability. |

## 7. Remaining decisions and release gates

Agree business timezone, shifts/corrections, bon policy/amount ceiling, evidence retention and disclosure, support process, backup/restore ownership, minimum OS/device matrix, app identity/signing, and billing/usage alerts. Exact backend knobs and setup commands are authoritative in the [backend guide](../cloudflare/README.md); the [TSD](TSD.md) explains technical boundaries and planned verification.

The implementation lead confirmed analyzer success and all 33 Flutter tests after durable recovery integration. The backend rerun passed 13 tests including Miniflare, plus Wrangler dry-run and local D1 migration. These checks do not establish production data/account checks or Android/iOS build/device/store readiness. See [verification evidence and limits](TSD.md#7-verification-and-release-limits) and follow the [migration plan](MIGRATION.md) before any real cutover.
