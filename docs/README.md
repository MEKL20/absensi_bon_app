# Absensi & Bon documentation

**Version 1.1 · 17 November 2026 (Asia/Jakarta).** This set describes the installed Flutter Android/iOS MVP being implemented: owner-managed employees, attendance with selfie, bon **without photos**, and a Workers + D1 + private R2 backend. Version 1.0 was a source-derived description of the prior Apps Script/Imgur client; its old flow is not the current contract.

| Document | Use it for |
| --- | --- |
| [PRD](PRD.md) | Confirmed product scope, roles, stable FR/NFR IDs, lifecycle invariants and release gates. |
| [TSD](TSD.md) | API/data contract, authorization, validation/retry behavior, platform limits, quotas/cost and verification plan. |
| [SDD](SDD.md) | Architecture/navigation, interactions, state/ownership diagrams and requirement traceability. |
| [BYOC proposal](BYOC.md) | Customer-owned environments, stack alternatives, onboarding, pairing and update design; not implemented. |
| [CI/CD guide](CI_CD.md) | Existing GitHub build workflows and signing configuration; native hosted runs remain unverified. |
| [ONBOARDING](ONBOARDING.md) | Customer-owned workspace creation, QR pairing, and manual Cloudflare/GitHub prerequisites. |
| [MIGRATION](MIGRATION.md) | Ordered setup, verification, data reconciliation, safe cutover and rollback preparation. |
| [Backend guide](../cloudflare/README.md) | **Authoritative exact backend commands/configuration**, owner bootstrap, bindings, migrations and operational caveats. |

Read PRD → TSD → SDD, then MIGRATION before operational setup. Mermaid-capable Markdown rendering is needed for diagrams. Relative source links support implementation review; no secrets, employee records or deployment IDs are copied here.

## Reading conventions

- **Confirmed requirement/target:** agreed behavior to implement and verify; not a deployment claim.
- **Implementation/source:** code exists or is being integrated; successful execution requires separate evidence.
- **Prior baseline:** obsolete client behavior included only to explain migration, never an automatic fallback.
- **Pending/unverified:** policy, account configuration, device behavior or execution evidence still required.

The explicit MVP assumption is one business per deployment. Owner/employee role enforcement belongs to the server. Employee removal means deactivation with retained history. Server ID/time and opaque bearer sessions replace client-supplied names/local times. Attendance alternates check-in/out across midnight. Bon moves from pending to approved/rejected, then disbursed and partially/fully repaid; only disbursed outstanding amounts count as debt. No demo state substitutes for a missing service. Durable pending recovery is implemented: save the request/key and attendance photo bytes before send in app-private storage scoped to API + user, restore after sign-in/restart, and block conflicting writes until resolved. Tokens/passwords are never persisted.

## Evidence and boundaries

Implementation references: [entry](../lib/main.dart), [API client](../lib/api_client.dart), [models](../lib/models.dart), [login](../lib/login_page.dart), [home](../lib/home_page.dart), [employee editor](../lib/employees_page.dart), [attendance](../lib/absensi_page.dart), [bon](../lib/bon_page.dart), [Worker](../cloudflare/src/index.js), [schema](../cloudflare/migrations/0001_initial.sql), and [password hashing](../cloudflare/src/crypto.js). The [manifest](../pubspec.yaml) now targets Dart 3.8+.

A local Flutter 3.32.8 / Dart 3.8.1 toolchain is bootstrapped. Dependency resolution updated the lockfile, but `pub get` exited 1 at plugin symlink setup because Windows Developer Mode is disabled. The implementation lead confirmed `flutter analyze --no-pub` exited 0 with no issues; `flutter test --no-pub --concurrency=1 --dart-define=CAPTURE_PREVIEWS=true` passed all 48 tests (28 API/workspace, six Cloudflare provisioning, five form, one layout, five onboarding, three startup/login). Coverage includes narrow 320×740 at 200% text, retained tab drafts, role navigation, recovery banner replay and dashboard refresh. Backend rerun passed all 15 tests including Miniflare and setup-token coverage, Wrangler dry-run, and local D1 migration. Customer-owned onboarding is implemented per [ONBOARDING](ONBOARDING.md); Cloudflare/GitHub deployment, R2 activation and digest-secret entry remain manual provider steps. No app/test/deploy commands were run by the documentation task. Android SDK and an iOS build host are unavailable; no mobile release build or device qualification is claimed.

No live deployment, historical import, existing account access, credential validation, actual Cloudflare account configuration, or Android/iOS release qualification has been performed here. Source changes do not establish signing, device camera behavior, store readiness, tested backup/restore, historical debt truth, or permanent free operation. See the [verification plan](TSD.md#7-verification-and-release-limits) and [cost constraints](TSD.md#6-free-tier-feasibility-and-cost).

## Preview provenance

[Sign-in](previews/sign-in.png), [employee home](previews/employee-home.png), [employee bon](previews/employee-bon.png), [owner home](previews/owner-home.png), and [pending recovery](previews/pending-recovery.png) are captured Flutter widget-renderer previews using controlled API fixtures and empty/recovery states for design review. They are not real-device screenshots, live backend evidence, production data, or demo state shipped in the app.

## Maintenance

Keep FR-01 through FR-07 and NFR-01 through NFR-06 stable; update acceptance coverage and diagrams together. Synchronize API field changes with client, Worker, schema and backend guide. Record actual check commands/results with scope and limitations when available. Resolve policy decisions explicitly; do not invent old attendance pairs, debt states or migrated balances.
