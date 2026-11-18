# Customer-owned deployment proposal

**Status: proposed, not implemented.** This note records the user’s goal that every business owns its environment and does not depend on the product developer’s cloud account for daily operation. It supplements the implemented baseline in the [PRD](PRD.md), [TSD](TSD.md), and [SDD](SDD.md).

## Ownership and recommendation

Recommend a shared installed Flutter application with one independent Worker, D1 database, and private R2 bucket in each business’s Cloudflare account. Each owner controls billing, deployment authorization, records, photos, and backup access. The product developer distributes software and optional support; ordinary authentication and record requests go directly to the selected business backend. No central workspace directory, API proxy, license check, or developer-held cloud credential is required for daily operation.

This is customer-owned hosting, not multiple organizations sharing one database. A shared mobile binary remains publisher-managed distribution; if the requirement also excludes the publisher’s app-store account, each owner must manage their own signing and distribution. That separate branded-app model has much higher onboarding effort, particularly on iOS.

## Stack alternatives

| Stack | Benefit | Cost or operational tradeoff | Recommendation |
| --- | --- | --- | --- |
| Flutter + Cloudflare Workers/D1/R2 | Reuses the current backend and provides isolated per-account resources. | Custom authentication and lifecycle management; R2 activation/billing and Workers CPU limits need qualification. | Preferred first prototype. |
| Flutter + owner-owned Supabase project | Managed Auth, Postgres, storage, and authorization primitives reduce custom backend work. | Substantial backend migration; free storage/egress limits and inactivity pausing; an authorized installer is still needed. | Best alternative if managed authentication outweighs migration cost. |
| Flutter + Appwrite on owner-owned VPS | Owner controls the server and application services. | Paid server, patches, backups, availability and recovery require operational ownership. | Use only with a maintenance provider or technical owner. |

Provider references researched in the conversation: [Cloudflare deployment buttons](https://developers.cloudflare.com/workers/platform/deploy-buttons/), [R2 activation](https://developers.cloudflare.com/r2/get-started/), [Supabase pricing](https://supabase.com/pricing), [Supabase Management API](https://supabase.com/docs/guides/platform/management-api), and [Appwrite self-hosting](https://appwrite.io/docs/advanced/self-hosting). Recheck current terms before implementation; separate owner accounts do not establish permanent free service.

## Proposed owner onboarding

1. Owner installs the shared mobile app and selects Create workspace.
2. A guided provider-owned deployment flow asks the owner to sign into their own Cloudflare and Git provider accounts, authorize deployment, and activate required services. Account creation, consent, and billing acceptance cannot be silently automated.
3. An isolated deployment template provisions Worker/D1/private R2, applies versioned schema migrations, and reports readiness. Current Cloudflare deploy-button documentation requires a public source repository and can copy the template into the customer’s Git account. A generic third-party Cloudflare OAuth integration is not assumed available.
4. The customer-hosted setup page verifies a high-entropy, expiring, single-use enrollment credential established through the authorized deployment process. It atomically creates the first owner and disables enrollment. A public first-visitor-wins setup is prohibited. The exact credential-delivery mechanism requires a tested prototype.
5. The authenticated setup page displays a workspace QR/configuration link containing a version, stable workspace ID, HTTPS origin, and display name. It contains no Cloudflare token, database password, owner password, or long-lived session credential.
6. The mobile app validates and displays the destination/business before pairing, checks API compatibility, and stores the workspace locally. The QR identifies a workspace; it does not authenticate an employee.
7. Employees receive the workspace pairing information through the owner, then sign into accounts created for that workspace.

## Runtime isolation and failures

Tokens, cached records, and pending requests must be isolated by workspace origin and stable user ID. Switching workspace clears the active session and visible data. An unresolved financial request must remain recoverable only against its original workspace; it must never be replayed against another origin. Endpoint changes require explicit re-pairing and identity validation. Do not silently redirect credential-bearing requests to another host.

Cloudflare management credentials stay in provider-authorized deployment tooling or customer-controlled CI. The employee/owner mobile application only holds application session credentials. Private R2 access remains behind the customer Worker. Provider account revocation must stop deployment management without redirecting business traffic to the developer’s account.

A failed deployment must be resumable without duplicate resources or another owner account. A quota failure must show a useful service error, not a successful record. A deleted backend must be treated as unavailable, not silently recreated with an empty database. Owner recovery and backups are customer-controlled and need a tested runbook.

## Updates without a developer-hosted service

Publish versioned backend releases and compatible mobile releases. Customer-controlled build automation may fetch an explicitly selected release, verify provenance, back up data, apply reviewed migrations, deploy, and run health checks. Repository cloning alone does not automatically deliver upstream updates.

For an initial version, use owner-triggered updates in the customer’s repository/provider account. An in-app Update button is later work: it needs an authorized customer-side deployment mechanism and cannot be implemented by embedding management credentials in Flutter. Keep a compatibility manifest so old mobile clients can recognize unsupported backend versions. Rollback must account for schema changes and writes made after an upgrade.

## Gap from the repository baseline

| Area | Current evidence | Required work |
| --- | --- | --- |
| Backend selection | [API client](../lib/api_client.dart#L28) defaults to build-time API_BASE_URL and holds one final base URL. | Runtime pairing, workspace storage/selection and endpoint identity checks. |
| Deployment | [Wrangler configuration](../cloudflare/wrangler.toml) has resource placeholders and workers_dev=false. | Customer deployment template, reachable endpoint provisioning and idempotent resource setup. |
| Owner enrollment | [Backend guide](../cloudflare/README.md) describes a local bootstrap utility. | Secure customer-hosted first-owner setup and recovery. |
| Mobile delivery | [CI/CD guide](CI_CD.md) describes shared Android/iOS build artifacts. | Published app distribution and workspace-compatible builds; no per-owner rebuild for configuration. |
| Updates | No customer update manager is established. | Versioned migrations, compatibility checks, customer-authorized deployment and restore rehearsal. |

## Acceptance gates for a prototype

- Provision two independent test businesses using separate owner accounts, with no developer runtime credential or account dependency.
- Pair the same mobile binary to either environment without recompilation.
- Reject cross-workspace authentication and data access; preserve pending writes against the original workspace across switches/restarts.
- Ensure enrollment expires, cannot be replayed, and cannot create a second first-owner through concurrent requests.
- Re-run interrupted deployment/upgrade without data loss or duplicate resources.
- Demonstrate quota handling, owner recovery, backup restore and account revocation.
- Measure deployed authentication CPU and retained photo usage before promising a Free-tier operating envelope.

No provisioning, QR pairing, enrollment endpoint, hosted installer, or update automation was added by this documentation proposal.
