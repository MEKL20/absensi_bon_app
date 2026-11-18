# Mobile workspace redesign

Mode: Operate. Platform: installed Flutter Android/iOS, adaptive mobile. The owner manages employee access and bon actions; employees record attendance and submit photo-free bon. Confirmed direction: full mobile, Cloudflare backend, attendance photos only, role-specific bottom navigation. User authorized continuation; routine design choices delegated through that instruction.

WORLD: precise roster and administrative journal, translated into familiar Material mobile controls. Light near-white surfaces suit phone use during the working day; dark evergreen actions, ink typography, mint selection, and semantic text statuses carry hierarchy.

STRUCTURE: owner overview routes to employee, attendance, and bon lists. Employee home routes to attendance, bon, account. One task form above its domain history; four persistent navigation destinations.

STORY: owner sees open work sessions, pending requests, and disbursed debt. Employee sees attendance state and the action to record it; bon requires only integer IDR and an optional note.

FIRST VIEWPORT: short AppBar, name and task context, a single dark attendance summary with primary action, then bon summary rows. Bon opens with amount/note and send action before history. No fabricated production records.

FORM: native Material3 controls and task-first roster lists; code-led. Assignment acknowledged; candidate6 administrative journal. Seed reference unavailable for persisted brief; do not expose assignment metadata in app.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance.

Verification boundary: Flutter widget renderer previews at390x844 logical pixels and narrow320x740 at200% text; no Android/iOS emulator or device is available. No native device qualification claimed.
