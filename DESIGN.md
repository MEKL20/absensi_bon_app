---
name: Absensi & Bon
description: Current Flutter native design system for attendance and employee cash advances.
colors:
  ink: "#152C31"
  muted: "#51636A"
  primary: "#17634C"
  background: "#F5F8F7"
  border: "#D7E1DC"
  surface: "#FFFFFF"
  summary-support: "#D8E8E2"
  avatar-surface: "#E5EFEA"
  status-warning: "#81580A"
  status-negative: "#A12D30"
  error-surface: "#FFF0EF"
  error-text: "#8C292D"
rounded:
  status: "8px"
  control: "12px"
  summary: "16px"
spacing:
  field-gap: "16px"
  page-inset: "20px"
  section-top: "24px"
  form-history-gap: "32px"
---

# Design System: Absensi & Bon

## Overview

This records the built Flutter Android/iOS interface. The current visual language is a precise administrative journal: light surfaces, dark evergreen actions, ink headings, and lists separated by rules. It supports phone use during the working day, short attendance tasks, and owner review of employee requests. The app uses Indonesian labels and integer rupiah amounts.

The implementation is the authority for visual values; [product context](PRODUCT.md) remains the authority for settled capabilities and open policy questions. The [surface brief](.impeccable/surface-brief.md) describes the current Operate surface. This document captures what exists rather than proposing another redesign. The machine-readable companion is [design.json](.impeccable/design.json); it uses the requested project-specific token structure, not a web component schema.

Key characteristics:

- Material 3 native Flutter controls and Material Icons; system/default Material typography.
- A single dark attendance summary establishes the next task; history uses readable rows.
- Four persistent navigation destinations vary by server-provided role.
- Forms show validation, progress, failure, and confirmed receipts in context.
- No external visual assets or custom fonts. Attendance photos are user-captured private evidence.

Source map: [shared colors, status and layout primitives](lib/ui.dart), [application theme](lib/main.dart), [sign-in](lib/login_page.dart), [role navigation and dashboard](lib/home_page.dart), [bon](lib/bon_page.dart), [attendance](lib/absensi_page.dart), and [employee management](lib/employees_page.dart). [The Flutter manifest](pubspec.yaml) enables Material Icons and declares no custom fonts or image assets.

## Colors

The five shared constants in [AppColors](lib/ui.dart#L4) establish the palette; additional colors below are observed component values.

| Token | Value | Current use |
| --- | --- | --- |
| ink | #152C31 | Theme on-surface color, headings, dark attendance summary |
| muted | #51636A | Supporting instructions, empty-state icons, metadata |
| primary | #17634C | Primary action/foreground and positive status text |
| background | #F5F8F7 | Scaffold, AppBar, receipt and photo-placeholder surfaces |
| border | #D7E1DC | Enabled field outlines, dividers, photo placeholder border |
| surface | #FFFFFF | Fields, navigation bar, theme surface and on-primary text |
| summary-support | #D8E8E2 | Supporting text on the ink attendance summary |
| avatar-surface | #E5EFEA | Employee initial avatar background |
| status-warning | #81580A | Diajukan / pending status text |
| status-negative | #A12D30 | Ditolak and Nonaktif status text |
| error-surface | #FFF0EF | ErrorNotice fill |
| error-text | #8C292D | ErrorNotice message text |

[The theme](lib/main.dart#L25) creates a light ColorScheme from the primary seed, then overrides primary, onPrimary, surface and onSurface. The mint navigation indicator comes from the generated primaryContainer; tonal button colors and other unoverridden roles remain Material-generated values. Do not freeze an inferred hex value for those roles from a screenshot. This app currently installs only a light theme.

[StatusBadge](lib/ui.dart#L69) uses its text color at 9% opacity for its background. Pending is warning, rejected/inactive are negative, and other statuses use primary. A visible localized label carries status independently of color. Dark summary text uses explicit white and summary-support colors in [the dashboard](lib/home_page.dart#L253).

## Typography

[ThemeData](lib/main.dart#L38) uses Material 3 without fontFamily or textTheme overrides. The shipping type comes from Flutter's default Material/platform font resolution; Android uses its Material Roboto default and iOS follows Flutter's platform font resolution. There is no downloaded font, custom typeface, or separate display/mono family. Preserve platform text scaling rather than copying preview glyph metrics as a fixed type system.

| Role | Actual implementation |
| --- | --- |
| Sign-in product title | headlineLarge with weight 700 and ink |
| Page greeting / team heading | headlineSmall with weight 700 |
| Section heading / bon amount | titleLarge |
| Employee name, form subheading, list total | titleMedium |
| Attendance summary heading | Explicit 20 logical px, weight 600, white |
| Attendance summary supporting text | Explicit 16 logical px, height 1.5 |
| Sign-in introduction | Explicit 17 logical px, height 1.5, muted |
| Dashboard outstanding amount | Explicit 20 logical px, weight 700, ink |
| Status label | Explicit 12 logical px, weight 600 |
| Receipt identifier | bodySmall |
| Instructions and body text | Inherited Material text; several instructions explicitly set height 1.5 |

These are actual textTheme role references, not a new fixed numerical scale. Headline and title role metrics remain Flutter Material defaults. Labels use sentence case, Indonesian task verbs, and explicit optional-field wording. [money and dateTimeLabel](lib/ui.dart#L12) format amounts as Rp with dot-grouped thousands and timestamps using Indonesian month abbreviations; the current timestamp formatter converts to the device's local time.

Icons use Flutter's Material Icons via Icons, predominantly outlined task symbols: badge, camera, fact-check, wallet, people, person and home. Refresh, send, check, login/logout and chevrons communicate actions. Typical icon sizing is inherited; explicit sizes include 32 for the sign-in mark/photo placeholder and 36 for an empty state. No icon image downloads or external icon family are used.

## Layout

All dimensions below are Flutter logical pixels. The app uses a single scrollable column, SafeArea, short AppBars and bottom navigation. There is no implemented desktop rail, multi-column breakpoint or dark variant.

| Surface | Existing constraint / inset |
| --- | --- |
| Shared PageBody | Top-centered, SafeArea, maximum width 680 |
| Login | PageBody; left/right 24, top 48, bottom 32 |
| Dashboard, account, employee list/form | PageBody; 20 all around |
| Bon and attendance domain content | SafeArea; left/top/right 20, bottom 32; centered inner maximum width 800 |
| Employee bon / attendance entry form | Left-aligned within domain column; maximum width 640 |
| Owner attendance photo dialog | Maximum width 560; scrollable content with 20 inset |
| Bottom NavigationBar | Height 76, before platform safe-area handling |

[PageBody](lib/ui.dart#L179), [bon layout](lib/bon_page.dart#L474), [attendance layout](lib/absensi_page.dart#L402), and [photo viewer](lib/absensi_page.dart#L173) are separate constraints; 640/680/800 are widths, not responsive breakpoints. Entry forms precede their history. Lists support pull-to-refresh; pagination exposes a text action and explains that search/filtering applies to loaded records.

Observed rhythm: 4/6/8 for tight metadata gaps; 10 for repayment detail separation; 12/16 between controls; 20 for page/summary padding; 24 for section starts and major form actions; 28/36 around the sign-in introduction; 32 between form and history. SectionHeading adds 24 above and 12 below. Bon records have 18 vertical padding. Choice/action Wrap layouts use 8 or 12 spacing and 8 run spacing. Error/receipt blocks use 16 padding; the attendance placeholder uses 24.

Global [button themes](lib/main.dart#L64) set a 48×52 minimum for filled buttons and 48×48 for outlined/text buttons. The bon and attendance form submit buttons explicitly override minimum height to 48. Attendance choice chips add 8 vertical label padding. Native IconButton, fields, switch and navigation targets inherit Material behavior; their physical effective sizes are not separately device-certified here. Long text and keyboard access rely on scrollable forms and wrapping layouts.

## Elevation & Depth

Custom containers use tonal contrast, one-pixel borders and dividers rather than custom shadows. The ink summary stands above the light background through color alone. AppBar scrolledUnderElevation is explicitly zero. Dialog elevation, navigation selection, control overlays and native press/focus feedback remain Material defaults. No custom shadow, easing or animation token system exists.

## Shapes

[Shared components](lib/ui.dart) and [the theme](lib/main.dart) use 8-radius status badges, 12-radius outlined fields/buttons/errors/receipts/photo previews, and 16-radius summary/sign-in-mark containers. Employee initials use CircleAvatar. Material defaults own navigation indicators, choice chips and dialogs; do not turn those into custom radius tokens. Attendance photo previews use a clipped 4:3 aspect ratio with BoxFit.contain. The owner photo dialog uses InteractiveViewer and contains the full image.

## Components

**Navigation.** [HomePage](lib/home_page.dart#L64) shows owner destinations Ringkasan → Karyawan → Absensi → Bon; employee destinations Beranda → Absensi → Bon → Akun. Navigation uses labeled Material NavigationDestination icons on white, with a generated mint selection indicator. IndexedStack preserves visited pages/drafts; returning to the dashboard triggers a data refresh. Owners sign out from an AppBar icon with a tooltip; employees have a labeled sign-out action on Akun. Role-specific UI follows authenticated identity and does not substitute for server authorization.

**Fields and actions.** White filled outlined inputs have 16 horizontal/vertical content padding, a 12 radius and border-colored enabled outlines. Focus, validation-error and disabled rendering follow Material defaults. Filled buttons mark the task action; outlined buttons mark camera capture, sign-out and owner bon actions; text buttons support retry, pagination and cancellation. Busy states disable relevant controls and retain a visible verb/progress label. Confirmation dialogs are scrollable.

**Sign-in.** [LoginPage](lib/login_page.dart) provides username/password autofill, keyboard next/done behavior, required-field errors, a tooltip-labeled password visibility toggle and an inline service-configuration error. Login becomes disabled without an endpoint. While checking credentials, the button says Memeriksa akun… and shows a spinner. Password recovery copy directs the employee to the owner; it does not claim an implemented self-service flow.

**Dashboard and lists.** [The dashboard](lib/home_page.dart#L225) shows open work sessions, pending bon count, disbursed outstanding amount, and up to five recent attendance/bon records. Rows use separators, clear titles, metadata and textual status badges. Employee avatars contain an initial, not a profile-photo asset. EmptyState uses a 36-size muted icon, title and explanatory text, with 32 vertical/16 horizontal padding. Empty and no-search-result messages differ.

**Bon.** [BonPage](lib/bon_page.dart) contains no camera, photo or upload. Employees enter digits-only integer rupiah and an optional note (2–5 visible lines, 500-character limit); the existing validator accepts 1 through 1,000,000,000 rupiah. That technical limit does not settle the open business maximum policy. Owners see status-dependent actions: pending → Setujui/Tolak; approved → Catat pencairan; disbursed with outstanding balance → Catat pembayaran. Dialog copy distinguishes approval from funds being handed over. Repayment validates a positive amount no greater than outstanding debt. The list total explicitly describes only the loaded history.

**Attendance.** [AbsensiPage](lib/absensi_page.dart) offers employees Masuk/Pulang choice chips, selfie instructions, an empty photo placeholder or 4:3 preview, camera capture/retake, then submit. Submission is disabled until a photo exists. Capture requests the front camera, quality 75, and maximum 1600×1600; Android lost-camera-result recovery is implemented. Owners see a searchable attendance list and a tooltip-labeled private photo viewer, rather than an employee submission form.

**Employee management.** [EmployeesPage](lib/employees_page.dart) provides owner-only search, initial avatars, active/inactive labels and a separate add/detail form. Name has a 100-character limit; username has 3–64 restricted characters and is read-only on edit. Initial password requires at least 12 characters; replacement password is optional on edit. SwitchListTile.adaptive changes account activity without deleting history. Saving disables the form and changes the action label.

**Feedback and recovery.** [ErrorNotice](lib/ui.dart#L102) is a full-width live-region notice with a retry text action when available. Loading uses linear progress for histories and compact spinners for busy submissions. Confirmed receipts are live regions with server-returned amount/kind, timestamp and ID. Bon clears fields only after confirmation; attendance clears its photo after confirmation. Uncertain bon submission locks the draft and labels its retry Periksa pengiriman; uncertain attendance locks kind/photo changes while retaining the same submission identity. Owner bon actions block other actions while an outcome is uncertain. [HomePage recovery](lib/home_page.dart#L144) offers a pending-request notice and result check; confirmed owner actions/recovery use SnackBars. Errors and zero-data states do not fabricate production records.

## Do's and Don'ts

- Do preserve the shared palette, Material typography and native task controls. Keep 48-logical-pixel action minimums and the existing width constraints when adding related screens.
- Do retain labels alongside color and icons. StatusBadge has a semantic status label, ErrorNotice/receipts use live regions, major icon actions have tooltips, and photos have semantic descriptions.
- Do keep forms scrollable and text scaling enabled. Use the existing wrapping action/status layouts; verify real content and long names rather than assuming a screenshot proves every state.
- Do preserve bon's optional note and photo-free flow, attendance's private selfie requirement, role-specific navigation, and the distinction between approval and disbursement from [product context](PRODUCT.md).
- Don't convert loaded-history totals or search results into claims about all historical records. Don't add absence/late classifications while schedules remain undecided.
- Don't introduce external fonts/assets as though they were part of this implementation. The preview font/icon loaders use Flutter SDK assets solely to render the actual widgets in the test harness.
- Don't treat widget previews as native-device qualification or deployment evidence.

Verification evidence and boundary: [mobile_layout_test.dart](test/mobile_layout_test.dart) renders MyApp/HomePage, uses an in-memory zero-record API fixture, and captures RepaintBoundary at 2× from a 390×844 logical viewport. The existing [sign-in](docs/previews/sign-in.png), [employee home](docs/previews/employee-home.png), [employee bon](docs/previews/employee-bon.png) and [owner home](docs/previews/owner-home.png) images are actual Flutter widget captures, not HTML recreations or external comps. The bon image contains a synthetic 125000 draft; names and zero totals are demonstration fixtures, not business records. The test also checks employee bon layout at 320×740 and 200% text scale, draft retention, dashboard refresh and no camera in bon. It does not certify every screen at 200% text. [Form tests](test/forms_test.dart) cover key validation, debt and uncertain-draft behavior; [sign-in tests](test/widget_test.dart) cover validation and endpoint absence.

No Android/iOS emulator or real-device review is established by these artifacts. TalkBack/VoiceOver reading order and duplicate announcements, actual target bounds, contrast in generated/disabled/focus states, dynamic text on every route/dialog, keyboard/IME overlap, camera permission/handoff/recovery, system insets, and intermittent network outcomes remain checks on the installed app. There is no claim of audited accessibility conformance, production data, completed deployment or device qualification.
