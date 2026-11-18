# Technical Specification Document (TSD)

> Proposed evolution: [customer-owned deployment (BYOC)](BYOC.md). Each business would own its environment; automatic provisioning, workspace pairing and customer updates are not implemented.

**Product:** Absensi & Bon Karyawan\
**Version:** 1.1 · 17 November 2026 (Asia/Jakarta)\
**Status:** Implementation and target contract; deployment and mobile release qualification pending.

Related: [PRD](PRD.md), [SDD](SDD.md), [documentation guide](README.md), [migration plan](MIGRATION.md). Exact backend configuration, commands, hash format, and operational caveats are authoritative in the [backend guide](../cloudflare/README.md).

## 1. Implementation boundary

The prior Apps Script/Imgur client is being replaced by a native Flutter mobile client and Cloudflare Workers + D1 + private R2. It is not a web/PWA. One business per deployment is the explicit MVP assumption; the schema is not a multi-tenant authorization model. These specs describe code and agreed target behavior, not a deployed service.

| Component | Responsibility / source |
| --- | --- |
| App entry and theme | Own API client lifecycle and start login; normal TLS, no permissive certificate override: [entry point](../lib/main.dart). |
| Login/home | Server user identity, role-specific dashboard/navigation, logout: [login](../lib/login_page.dart), [home](../lib/home_page.dart). |
| API client/models | HTTPS endpoint configuration, bearer memory session, typed requests/receipts, timeouts: [API client](../lib/api_client.dart), [models](../lib/models.dart). |
| Forms | Owner account management, employee attendance/selfie, bon without photo and owner actions: [employees](../lib/employees_page.dart), [attendance](../lib/absensi_page.dart), [bon](../lib/bon_page.dart). |
| Shared presentation | Status labels, form/empty/error surfaces: [UI helpers](../lib/ui.dart). |
| Backend | Role/ownership checks, validation, server ID/time, receipts, R2 access: [Worker](../cloudflare/src/index.js), [schema](../cloudflare/migrations/0001_initial.sql), [password hashing](../cloudflare/src/crypto.js). |

The [manifest](../pubspec.yaml) now requires Dart `>=3.8.0 <4.0.0`, declares HTTP, image picker, path provider and Flutter lints. An isolated local Flutter 3.32.8 / Dart 3.8.1 toolchain has been bootstrapped. Dependency resolution updated the lockfile, but `pub get` exited 1 at plugin symlink setup because Windows Developer Mode is disabled. The implementation lead confirmed `flutter analyze --no-pub` exited 0 with no issues. The final mobile suite passed all 33 tests after durable recovery integration. This is not an Android/iOS build claim.

## 2. Transport and sessions

The mobile app receives a public HTTPS base URL via compile-time `API_BASE_URL`; it must not include userinfo, query, or fragment. An absent/invalid URL shows configuration failure. No bundled owner password, Worker/R2 credential, seeded demo, offline success, or legacy fallback is permitted.

Login sends JSON `{username,password}` to `POST /v1/auth/login`; username is normalized, password whitespace preserved. Response is `{ok:true,token,user}`. User fields: `id`, `name`, `username`, `role` (`owner|employee`), and boolean `active`. The opaque random bearer token is held only in API-client memory. D1 stores its hash and expiry, not the plaintext token. Protected requests use `Authorization: Bearer <token>`; server derives actor identity and checks active account and ownership on every request. Logout revokes that token; password reset/active changes revoke employee sessions.

JSON success requires both a 2xx HTTP status and `ok:true`. Errors use `{ok:false,error:{code,message}}` with safe messages; common statuses are 400 validation, 401 authentication, 403 role, 404 record, 409 duplicate/transition conflict, 413 size, 415 content type, 429 login limit, 500 uncertain server failure. Attendance photo success is binary, not JSON. Neither HTTP 200 alone nor legacy text tokens are an acknowledgement.

## 3. API contract

Paths are relative to the configured HTTPS origin. This table is the coordinated v1.1 contract; keep it aligned with the [backend guide](../cloudflare/README.md) and [client](../lib/api_client.dart) as implementation changes.

| Method/path | Access | Body / result |
| --- | --- | --- |
| `POST /v1/auth/login` | Public, rate limited | JSON credentials → `token,user`. |
| `GET /v1/auth/me` | Signed in | `user`. |
| `POST /v1/auth/logout` | Signed in | Revoke current token → `ok:true`. |
| `GET /v1/dashboard` | Both roles | `summary,attendance,bon`; employee scoped to self. |
| `GET /v1/employees` | Owner | `employees,pagination` (employee accounts only). |
| `POST /v1/employees` | Owner | `name,username,password` → `user`; role is always employee. |
| `PATCH /v1/employees/{id}` | Owner | Any supported `name,active,password` update → `user`; username/role immutable. Deactivation is the MVP delete operation. |
| `GET /v1/attendance` | Both roles | `attendance,pagination`; owner business scope, employee self scope. |
| `POST /v1/attendance` | Employee | Multipart `kind=check_in` or `check_out`, binary `photo`; idempotency required → `record`. No supplied employee ID/time. |
| `GET /v1/attendance/{id}/photo` | Owner / record employee | Authorized private binary image; no public object URL or persistent bearer query. |
| `GET /v1/bon` | Both roles | `bon,pagination`, same role scope. |
| `POST /v1/bon` | Employee | JSON `amount,note`; idempotency required → `record` in pending state. No photo field. |
| `POST /v1/bon/{id}/actions` | Owner | JSON `action` (`approve`, `reject`, `disburse`, `repay`); `amount` only for repay; idempotency required → `record`. |

List pagination uses `limit` (default 20, max 100), `offset` (default 0, max 100000), and response `pagination={limit,offset,hasMore,nextOffset}`. Attendance/bon additionally accept `from/to` as `YYYY-MM-DD`, filtering UTC recorded/created timestamp ranges. The mobile attendance, bon, and employee lists request pages of up to 100 and provide load-more; search/status filters apply to loaded records. Offset pages may shift as new records arrive, so refresh from offset zero after mutations. These lists are not a complete historical export; dashboard aggregates cover the full authorized scope.

Dashboard summary includes `employeeCount`, `checkedInCount`, `pendingBonCount`, `outstandingAmount`. `checkedInCount` means currently open check-ins among active employees (self-scoped for employee), including overnight sessions; it is not the number of today’s check-ins. Recent record arrays are bounded. Dashboard totals come from server queries, not list-window calculations.

## 4. Data and validation

| Entity | Contract and rules |
| --- | --- |
| User | Server UUID, name 1–100 characters, case-insensitive unique username 3–64 letters/digits/dot/underscore/hyphen, password 12–128 characters, fixed role, active flag. Credentials never appear in read responses. |
| Attendance | `id,employeeId,employeeName,kind,recordedAt,photoPath`; UTC ISO timestamp from server. Alternating state per employee is enforced transactionally, allowing check-out after midnight. Private R2 key stays internal; photo path is a protected API route. |
| Bon | `id,employeeId,employeeName,amount,note,status,repaidAmount,createdAt`; integer IDR, positive amount within configured maximum, note up to 500 characters. No photo field or object. |
| Financial audit | Actor, bon ID, action, amount, previous/next status, cumulative repayment, server time, and mutation claim. No guessed historical states. |
| Session / receipt | Hashed token + expiry; actor/key/payload fingerprint and accepted response for idempotency. See schema for constraints/indexes. |

Current backend ceiling defaults to Rp1,000,000,000 with an SQL hard bound Rp1,000,000,000,000. The shipped client ceiling and backend configuration must agree before use; this is a technical guard, not a business lending policy. Session TTL defaults to 86400 seconds; business timezone defaults to Asia/Jakarta. Photo retention defaults disabled (`PHOTO_RETENTION_DAYS=0`), which means accepted photos are retained until an explicit policy/configuration changes it. Refer to the [backend guide](../cloudflare/README.md) for supported ranges and exact behavior.

Attendance images are at most 2 MiB; backend checks supported JPEG/PNG/WebP signatures/content type. Picker quality/dimensions reduce typical payload size but do not guarantee the limit, selfie authenticity, or full image decoding. Android lost-picker-data recovery exists in the form; permission, interruption, and camera output still require real-device checks.

Bon transition invariant: pending → approved/rejected; approved → disbursed; disbursed → disbursed on partial repayment or repaid on full repayment. Repayment must be a positive integer at most the remaining balance. Only disbursed balances count as debt. Owner actions are accounting confirmations, not payment integrations.

## 5. Reliability and privacy

Attendance create, bon create, and bon actions send an `Idempotency-Key`. The backend fingerprints actor/method/path/semantic payload (including attendance image hash), stores receipts with D1 mutations, rejects key reuse with changed content, and guards concurrent state transitions. The client must retry the same uncertain request with the same key and payload. Account CRUD is not covered by this mutation receipt flow: reload/check username after an ambiguous creation instead of blind repetition.

Current client deadlines are 30 seconds for JSON/private-photo reads and 60 seconds for attendance multipart. A timeout does not cancel or roll back a server write. Durable recovery is implemented through the [pending store](../lib/pending_store.dart): save the immutable request path, key, payload and attendance photo bytes in a path-provider app-private file before send, scoped to API base URL + authenticated user ID. Tokens/passwords remain memory-only. After sign-in/restart, restore that scope and use the Home recovery banner to replay the unchanged operation. One unresolved operation blocks conflicting writes; draft fields and owner action/repayment values stay locked until resolution. Malformed typed receipts, including malformed HTTP 200, are uncertain and retain the envelope. This recovers an attempted operation; it is not a general offline submission queue.

D1 and R2 do not share a transaction. Before uploading, the Worker stores a durable pending photo intent with a lease; an accepted attendance transaction commits its intent and receipt together. Cleanup claims expired unreferenced intents, blocks late record commits through a database trigger, and retains deletion tombstones to repeat cleanup after delayed uploads. Accepted references are excluded from orphan cleanup. Ambiguous commit failures preserve evidence for reconciliation. This recovery is independent of destructive retention, which deletes eligible attached photos in bounded batches only when explicitly enabled. Follow the [backend guide](../cloudflare/README.md) for exact leases/batches; monitor intent/tombstone growth and verify backup/restore operationally. Private bucket access must stay disabled for public domains and r2.dev.

The previous TLS bypass, query credentials, public image upload, and bon-photo flow are prior-baseline risks addressed by replacement source. Assess/redact any remaining legacy backup keys and rotate real exposed credentials through the authorized operator; removing text from active source does not revoke a key. No credential validity or provider account was checked.

## 6. Free-tier feasibility and cost

These are planning allowances, **not a hard zero-cost cap or service guarantee**. Recheck the account plan and linked official terms before deployment.

| Service | Published Free allowance / constraint | Consequence |
| --- | --- | --- |
| [Workers](https://developers.cloudflare.com/workers/platform/limits/) | 100,000 requests/day; 10 ms CPU per request on Free. | Requests may fail at limits; low traffic alone does not establish CPU feasibility. |
| [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) and [limits](https://developers.cloudflare.com/d1/platform/limits/) | 5 million rows read/day, 100,000 rows written/day; 5 GB account total storage, **500 MB per Free database**. | Rows scanned/index maintenance/session and receipt writes count; the single MVP DB cannot use the whole 5 GB. Exceeding Free quotas can stop queries/writes. |
| [R2 Standard](https://developers.cloudflare.com/r2/pricing/) | 10 GB-month storage, 1 million Class A and 10 million Class B operations/month included. | Standard allowances have billed overage, not a hard storage stop. No Internet egress charge does not make storage/operations unlimited. |

Estimate retained photos as active employees × events/day × average compressed bytes × retention days; include retries, review reads, and other account workloads. Configure usage/billing alerts and monitor actual D1/R2/Worker metrics.

The [hash implementation](../cloudflare/src/crypto.js) uses standard WebCrypto PBKDF2-HMAC-SHA256 with 600,000 iterations, a random 16-byte salt and 256-bit output in a versioned format. The backend agent reports published-vector/native equality checks and verification of a Node-generated credential in installed workerd; no custom chained algorithm or weaker fallback remains. See the authoritative [backend guide](../cloudflare/README.md) for format and local benchmark evidence. Actual deployed Worker CPU for login and employee create/reset still requires measurement: Node/local timings do not prove compliance with the Free 10 ms budget. If it does not fit, choose a suitable paid/auth service design; do not weaken password hashing to claim free operation.

## 7. Verification and release limits

No app/tests/deployment were run as part of this documentation task. Lead-reported final evidence: `flutter analyze --no-pub` exited 0 with no issues; `flutter test --no-pub --concurrency=1 --dart-define=CAPTURE_PREVIEWS=true` passed all 33 tests (25 API, five form, one layout, two login). Layout coverage includes narrow 320×740 at 200% text, tab-draft retention, role navigation, pending-recovery banner replay and dashboard refresh. Backend rerun passed all 13 tests including Miniflare; Wrangler dry-run bundled 30.45 KiB (8.66 KiB gzip); local D1 migration completed 24 commands. These were local checks, not deployment. Flutter widget render previews use an empty API fixture, not production data or a device capture; see [preview provenance](README.md#preview-provenance). No live account, historical import, actual R2/D1 account policy, release APK/IPA, signing, or store publication was validated. Android SDK and an iOS build host are unavailable in this environment.

| Check ID | Requirements | Required evidence |
| --- | --- | --- |
| V-01 | FR-01, FR-02, NFR-01 | Owner/employee login/logout; inactive/reset/expired sessions rejected; cross-employee and employee-to-owner access denied. |
| V-02 | FR-03, NFR-05 | Device camera capture/retake/cancel, permission denial, Android picker recovery and iOS permissions. Bon never asks for camera. |
| V-03 | FR-04, FR-06 | Alternating attendance, overnight pair, concurrent duplicates, server ID/time, accepted receipt and retained failed draft. |
| V-04 | FR-05, FR-06 | No photo in bon UI/API; zero/overflow/max/note limits, all transitions, partial repayment, overpayment and concurrent action rejection, audit consistency. |
| V-05 | FR-06, NFR-02, NFR-06 | Lost response/malformed HTTP 200; durable save-before-send, restart/login scope isolation, same-key/photo replay, conflicting-write and draft/action locks, changed-body conflict and account-create reconciliation. |
| V-06 | FR-07, NFR-03 | Private R2/photos, owner/self access only, retention, ambiguous write/orphan handling, redacted logs and backup/restore. |
| V-07 | NFR-01, NFR-06 | Invalid certificates rejected, login rate limits, KDF and CPU profiling on intended deployment plan. |
| V-08 | NFR-04, NFR-05 | Dependency/plugin setup, analyzer/tests, Android/iOS release builds/signing, large text/keyboard/navigation, real-device camera/network checks. |
| V-09 | FR-04, NFR-02 | Clock skew, UTC filters/business timezone display, midnight boundary and replay ordering cannot alter canonical times. |

Use isolated test data/environments. Any passing local checks must retain their scope; they do not certify deployment, payment truth, mobile distribution, or historical balances. Follow the [migration plan](MIGRATION.md) for setup/cutover.
