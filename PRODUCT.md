# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Full installed Flutter mobile application for Android and iOS. No web/PWA frontend is planned.

## Users

The owner manages employees, attendance, and employee bon requests from a phone. Employees record attendance and submit bon requests from their phones. These roles and mobile delivery were confirmed in the conversation; the user authorized continuing implementation.

## Product Purpose

Help a business owner understand attendance and act on employee cash advance requests, while keeping employee entry fast and understandable.

## Capabilities and Constraints

- Keep Flutter. Cloudflare Workers is the API, D1 stores structured records, and private R2 stores attendance photos.
- Bon has no camera, photo, image upload, or photo-storage requirement. Amount is integer rupiah; the existing optional note remains optional unless policy changes.
- Attendance retains camera photos. Check-in/check-out, history, owner employee management, and bon approval/disbursement/repayment are the accepted implementation direction.
- Owner and employee navigation differs, but both are part of one mobile app. Server-side identity and authorization determine role.
- Target Cloudflare free allowances through bounded uploads, indexed queries, and explicit retention; no permanent zero-cost guarantee.
- No business accounts, production credentials, historical exports, or Cloudflare account access were provided. Deployment and data migration cannot be represented as completed.

## Operating Context

Indonesian interface and rupiah amounts. Phone use includes camera handoff and imperfect networks. Server receipts determine canonical timestamps.

## Implementation Assumptions and Open Decisions

- Implement one business per deployment for the initial release, without assuming a multi-owner SaaS. This is an explicit implementation assumption, not a confirmed business restriction.
- Expected employee count, working days, shift rules, photo retention, maximum bon policy, and release distribution remain open. Do not fabricate absence/late classifications without a schedule.
- Use Asia/Jakarta as a configurable initial business timezone, inferred from the working context.
- Start with in-memory mobile sessions; persistent secure sessions and password recovery are follow-up requirements before broad rollout.

## Evidence on Hand

Existing Flutter screens and repository analysis under docs. No current runtime screenshots, logo, proprietary fonts, production employee dataset, or backend source was supplied. Do not invent live business records or portray demonstration data as real.

## Product Principles

- Owner sees actionable records; employee sees the next task.
- Show confirmed server outcomes and preserve drafts when outcomes are uncertain.
- Approval is distinct from disbursement; only disbursed money becomes outstanding debt.
- Keep attendance photos private; bon never needs a photo.
