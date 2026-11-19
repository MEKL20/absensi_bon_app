# Cloudflare backend

Workers ES modules + D1 + a private R2 bucket. This folder is independent of Flutter. No live account resources or deployment were changed. Node 24.16+ is required for the SQL-backed tests.

## Local setup

Run from this directory:

```sh
npm ci
npm test
npm run check
npm run db:migrate:local
npm run bootstrap
npx wrangler d1 execute absensi-bon --local --file=bootstrap-owner.sql
npm run dev
```

The local bootstrap CLI prompts for name, username, and a hidden, confirmed 12–128 character password, then writes SQL with only a salted password hash. Its output is ignored by Git; delete it after applying it and restrict Windows ACLs as needed (POSIX mode 0600 is not a Windows ACL guarantee). SQL bootstrap also marks the workspace claimed; skip it if you intend to test Flutter's owner setup. The canonical Wrangler config uses `workers_dev = true` for each owner-provisioned Worker URL. Local tests inject explicit D1/R2 bindings and do not use or alter an account. Native Flutter requests do not need CORS; no browser CORS origin is enabled by default.

## Deploy one customer workspace

1. **Publish the template (maintainer).** Configure this `cloudflare/` directory as the public template subdirectory, using its canonical [wrangler.toml](<wrangler.toml>), package metadata, migrations and source. The [official Deploy button](https://developers.cloudflare.com/workers/platform/deploy-buttons/) uses the URL form `https://deploy.workers.cloudflare.com/?url=<PUBLIC_TEMPLATE_REPO_URL>`. Do not publish local state, generated SQL or customer secrets. The [secret declaration example](<.dev.vars.example>) contains no value.
2. **Generate a setup token (customer).** Use a password manager or a trusted offline generator to create a fresh token with 32 random bytes (for example, encoded as 64 hex characters). Keep it private until you enter it in Flutter. Compute SHA-256 over the UTF-8 text of the exact token, without a trailing newline. This example shows only the hex digest in a private PowerShell 7.2+ terminal:

   ```powershell
   $token = Read-Host 'Setup token' -MaskInput
   [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($token))).ToLowerInvariant()
   Remove-Variable token
   ```

3. **Deploy into your own Cloudflare account.** Provision a **new D1 database and new R2 bucket for this workspace**; do not reuse another workspace's data resources. Keep `r2.dev` and R2 public custom domains disabled. Use `npm run deploy` as the deploy command: its predeploy hook applies migrations by the `DB` binding, regardless of the database name. The package metadata describes both data bindings and the optional `OWNER_SETUP_TOKEN_SHA256` Worker secret. Missing secret does not block deployment, but owner setup remains unavailable until the secret is configured. Never put the raw token in HTML, Git, build logs, the Cloudflare secret, command arguments, or a QR code.
4. **Set up the optional digest secret.** After deployment, open **Workers & Pages → your Worker → Settings → Variables and Secrets** and add `OWNER_SETUP_TOKEN_SHA256` as type **Secret**, entering only the 64-character digest. If the actual template UI supplies an appropriate secret prompt, it may be used; this behavior has not been verified. The official Deploy button documentation describes resource provisioning and binding descriptions, not confirmed entry of this secret. Missing digest does not block deployment but does disable owner setup (503) until configured. Never enter the raw setup token into Cloudflare. The UI and live deployment were **not** tested on an account.
5. **Claim and pair.** Copy the HTTPS `workers.dev` URL from the dashboard. Open `/v1/workspace` on that URL to verify the workspace; an unclaimed workspace returns `ready: false`. In Flutter's owner setup, enter the URL, private raw token, owner details, and workspace name. After claim the endpoint reports `ready: true`. Pair other devices with the workspace QR, which must contain only public connection details. Pairing is not authentication: employees still sign in with accounts created by the owner.

Claim state is stored in D1 and does not reset when a Worker version or secret changes. If the setup response is lost after a successful claim, sign in with the new owner credentials; replay does not issue another setup session. There are no default credentials or general public signup. Missing setup configuration does not prevent existing users from signing in. A Worker rollback does not roll back D1, but restoring a **pre-claim** D1 backup restores the old claim state; retain the claim marker when recovering and never reuse the old setup token.

## Flutter provisioning assets

`npm run bundle:app` rebuilds `../assets/cloudflare_worker.js` (esbuild bundle of `src/index.js`) and `../assets/cloudflare_migrations.json` (ordered migrations). The mobile automatic-setup flow uploads these assets to the owner account; rerun it after Worker or schema changes and release a new app build.

## API contract

JSON success responses include ok:true except for minimal workspace discovery. Errors are always {ok:false,error:{code,message}}. Session tokens are opaque 32-byte random values; send Authorization: Bearer <token> to authenticated endpoints. D1 stores SHA-256 token hashes, not bearer values. Auth uses current user role and active state on every request; expired, logged-out, inactive and reset-password sessions fail with 401. Password and active changes revoke all employee sessions atomically. Owners can manage only employee accounts; client role fields are rejected.

| Method / path                | Access               | Request / result fields beyond ok                                                               |
| ---------------------------- | -------------------- | ----------------------------------------------------------------------------------------------- |
| GET /v1/workspace            | Public               | Exactly {id,name,ready}; no secrets or account details                                           |
| POST /v1/setup/owner         | One-time setup token | {setupToken,name,username,password,workspaceName} → {token,user}, 201                              |
| POST /v1/auth/login          | Public, rate limited | {username,password} → {token,user:{id,name,username,role,active}}                               |
| GET /v1/auth/me              | Authenticated        | {user}                                                                                          |
| POST /v1/auth/logout         | Authenticated        | Empty success                                                                                   |
| GET /v1/dashboard            | Authenticated        | {summary:{employeeCount,checkedInCount,pendingBonCount,outstandingAmount},attendance:[],bon:[]} |
| GET /v1/employees            | Owner                | {employees:[user...],pagination} (employee accounts only)                                       |
| POST /v1/employees           | Owner                | {name,username,password} → {user}                                                               |
| PATCH /v1/employees/:id      | Owner                | {name?,active?,password?} → {user}                                                              |
| GET /v1/attendance           | Scoped               | {attendance:[{id,employeeId,employeeName,kind,recordedAt,photoPath}],pagination}                |
| POST /v1/attendance          | Employee             | multipart kind=check_in/check_out + photo=file → {record:attendanceRecord}, 201                 |
| GET /v1/attendance/:id/photo | Scoped               | Authorized binary, detected MIME, no public URL                                                 |
| GET /v1/bon                  | Scoped               | {bon:[{id,employeeId,employeeName,amount,note,status,repaidAmount,createdAt}],pagination}       |
| POST /v1/bon                 | Employee             | {amount,note?} → {record:bonRecord}, 201                                                        |
| POST /v1/bon/:id/actions     | Owner                | {action:approve/reject/disburse/repay,amount?} → {record:bonRecord}                             |

Owner setup requires a valid configured digest. Missing or invalid configuration returns 503 (setup_unavailable); an invalid or missing request token returns 401 (invalid_setup_token); a valid attempt after claim returns 409 (workspace_claimed). Owner, workspace metadata and the hashed session are committed in one D1 batch. The setup token is hashed and compared with the Workers runtime timing-safe primitive; only the login-compatible session token is returned.

User active is a JSON boolean. Employee reads include only their own attendance, bon and summary; owner reads include everyone. Owners do not submit personal attendance/bon. Employee dashboard employeeCount=1; owner employeeCount counts active employees. checkedInCount counts active employees with a currently open check-in, including check-ins from a previous business date. pendingBonCount counts all scoped pending requests. outstandingAmount sums all disbursed principal minus repayments; approval is not debt. Dashboard arrays include the newest 10 records each and are previews, not totals. Use the list endpoint for more rows.

Attendance uses an atomic SQLite state trigger: first check_in, then check_out, repeating across midnight. No daily uniqueness, late/absence rule, shift schedule, or client time is invented. All timestamps come from the server in UTC; a separate business_date is computed with BUSINESS_TIMEZONE (default Asia/Jakarta). Photos are mandatory on attendance, at most 2 MiB (2,097,152 bytes), and must have JPEG/PNG/WebP magic bytes. The upload's name is ignored; R2 names use server UUIDs. The detected MIME is authoritative. A matching MIME, omitted MIME, or Flutter's application/octet-stream is accepted; a conflicting claimed image MIME is rejected. Magic-byte validation is not a full image decoder, malware scanner, or EXIF remover. Bon has no photo fields or upload route; extra JSON fields and multipart bon requests are rejected.

Attendance, bon and employee lists accept limit (default20, 1–100), offset (default0, 0–100000), from/to inclusive YYYY-MM-DD dates. Dates filter UTC recordedAt/createdAt, not local business dates; employee lists use limit/offset only. pagination={limit,offset,hasMore,nextOffset}; nextOffset is null on the last page. Stable ordering uses timestamp then ID descending. Offset pages can shift while new records arrive; refresh from offset0 after mutations. No implicit deletion or hidden date window is applied. List size is bounded even without date filters. Username allows ASCII letters/numbers/._- (3–64), normalized lowercase; name 1–100 trimmed characters.

All attendance/bon writes and owner bon actions require Idempotency-Key: 8–128 ASCII letters/numbers/._:-. Generate a random UUID for each intended action and retain it across network retries. Scope is actor + key; fingerprint includes method/path and normalized request payload (attendance includes the bytes' SHA-256). Repeating returns the original stored record and HTTP status, even after later state transitions; a changed payload gives 409. Successful receipts are retained without automatic expiry to avoid accidentally duplicating old money actions. A rejected transaction rolls back the receipt so it can be retried after fixing state.

Money is positive safe-integer currency units (IDR in the app); no floating point conversion. Default maximum principal is 1,000,000,000; note is optional, max500 characters. State transitions: pending → approved/rejected; approved → disbursed; disbursed → disbursed/repaid. Only repay accepts amount and it must be positive and no more than outstanding debt. A single D1 transactional batch claims idempotency, conditionally updates state/debt, checks changes() with a CHECK-constrained guard, writes audit, and stores the exact response. Concurrent invalid state transitions/overpayments roll back completely; employees cannot act on their own or anyone else's requests.

## Security and password work factor

Credentials use standard WebCrypto PBKDF2-SHA-256 with 600,000 iterations, 16 random salt bytes and a 256-bit output, encoded as pbkdf2-sha256$v1$600000$<saltHex>$<hashHex>. Both Node and the installed workerd runtime accept this work factor directly. Published PBKDF2 vectors and Node native PBKDF2 equality are tested; a Node-generated credential is verified inside workerd. There is no custom chained algorithm and no weaker fallback. Keep this format stable for existing accounts; future changes need an explicit rehash migration.

Run npm run benchmark to measure this machine. Node v24.16.0 sample: hash 95.59 ms, verify 79.51 ms; combined process CPU 171 ms. These are local Node measurements, not production Worker CPU or Cloudflare billing figures. Workers Free provides a 10 ms/request CPU allowance: this password work is intentionally expensive and Free authentication must not be assumed viable. Verify actual deployed CPU before rollout and budget a paid Workers plan (or an explicitly designed external identity system). Do not reduce the hash to force Free eligibility. Local workerd tests validate KDF/runtime compatibility, not Free quota compliance. See https://developers.cloudflare.com/workers/platform/limits/ and https://developers.cloudflare.com/workers/runtime-apis/web-crypto/.

Login limiting is persisted in D1 and atomically increments separate SHA-256 IP and normalized-account buckets in a 15-minute window. Requests above 30/IP or 10/account are rejected; successful attempts also count. This is deliberately conservative, with no success reset that could race another login. Unknown/inactive/wrong-password errors use the same message; unknown accounts perform the same KDF. Never log passwords, tokens, or request bodies. Only Cloudflare's trusted CF-Connecting-IP header is used in production; local dev shares one fallback bucket. TLS is mandatory outside localhost. Rate limiting protects CPU but does not replace platform abuse controls.

## Operations and retention

| Variable             | Default      | Allowed values                                   |
| -------------------- | ------------ | ------------------------------------------------ |
| BUSINESS_TIMEZONE    | Asia/Jakarta | Valid IANA timezone; invalid config fails closed |
| SESSION_TTL_SECONDS  | 86400        | 300–2592000                                      |
| MAX_BON_AMOUNT       | 1000000000   | 1–1000000000000; SQLite hard cap 1e12            |
| PHOTO_RETENTION_DAYS | 0            | 0 disabled, 1–36500 explicitly enables deletion  |

Daily cron removes expired sessions and stale login counters. Destructive photo retention is disabled until a policy is agreed and explicitly configured. When enabled, cron deletes up to100 older referenced R2 photos per run and sets their photoPath reference to null while retaining attendance records. Deleting R2 first makes retry safe; if the DB reference update fails, the next run repeats the delete. There is no automatic bon/audit/idempotency retention or deletion policy.

Before each R2 PUT, D1 stores a durable pending upload intent with a one-hour lease. Attendance insert checks that lease and changes it to committed atomically with the record. A definitive SQL constraint rollback or confirmed duplicate moves its unused intent to deleting and removes the object. An ambiguous error preserves the intent/object until cron reconciles it. Cron atomically marks expired unreferenced pending intents as deleting; an accepted attendance reference cannot be claimed by this cleanup. The database trigger blocks a late insert after cleanup has claimed its intent. Cleanup checks references again before deleting; persistent tombstones repeat deletion daily so a delayed PUT after an earlier delete is eventually removed. Up to100 deleting intents are reconciled per cron run. Tombstones are retained; monitor growth before adding any eventual pruning policy. Referenced accepted photos are never orphan-cleaned, regardless of lease expiry. This orphan recovery is independent of destructive retention, which remains disabled by default. R2 and D1 cannot participate in one atomic transaction. Back up D1 before migrations and review audit records on disputes. Preserve R2 and D1 together when restoring. Password resets and deactivation use owner employee management; no unsafe password recovery HTTP route exists.

## Validation

npm test uses node:test with actual node:sqlite transactions for route authorization, session expiry/logout/revocation, persistent login limits, role escalation rejection, bon without photos, idempotency collisions/replays, concurrent overpayment, upload rejection, private binary access and retention. A separate Miniflare test runs the actual Worker module with real D1/R2 emulation, including WebCrypto credentials, invalid/missing setup tokens, unclaimed/claimed workspace discovery, concurrent owner claims and replay, and concurrent repayments. SQL constraints and triggers are executed, not mocked. npm run check bundles through Wrangler with deploy --dry-run; it does not deploy. npm run benchmark measures local hashing cost. No production/account integration, real device camera, actual billing/CPU quota or live R2/D1 behavior is claimed by these local checks.
