# JagSpoor v4.2 — Complete Functionality Report for Marketing

Generated: 11 October 2026 from `main` @ `8b0d641`
Repository: JagSpoor_v4_2 · Product version: **1.0.11+13** (build 13) · Platform: Flutter (Android + iOS) · Currency: ZAR
This document is a marketing-oriented feature inventory compiled read-only from the source tree. No code was changed.

---

## Executive Summary

JagSpoor is the all-in-one digital companion for the South African hunter and the outfitters who host them. For hunters, it turns a phone into a bushveld command centre — live tracking of a firearm licence from the DFO all the way to collection, a digital firearm safe, on-device ballistics, AI spoor identification, offline topographic maps, and a trophy room that remembers every hunt. For outfitters, it is a complete farm-management and marketplace platform — publish hunting packages, manage price lists and trophy stock, receive and approve booking requests, and track revenue, all in one place. A single app, two roles, one shared marketplace connecting hunters and outfitters across South Africa — online, offline, and off-grid.

---

## App Overview — What is JagSpoor?

JagSpoor is a multi-sided marketplace and field toolkit that connects South African hunters with outfitters and game farms, wrapped in a deep set of tools a hunter actually uses in the veld.

- **Two roles, one login.** A user registers as a Hunter or an Outfitter (superusers can hold both, and admins can switch freely). Every screen, marketplace action, and document is scoped to the correct role.
- **Hunter mode** gives the individual hunter a full field kit: licence tracking, firearm and ammunition management, ballistics, species guides, trophy logging, maps, and booking tools.
- **Outfitter mode** gives a farm or hunting operation an enterprise control panel: farms and managers, trophy stock, price lists, published packages, booking workflow, permits, and business analytics.
- **The marketplace in the middle** lets hunters discover and book real hunting packages and trophy animals from verified outfitters, and lets outfitters sell directly.
- **Offline-first by design.** Species guides, maps, trophy data, and field logs work with no signal — important in the deep bushveld where connectivity is unreliable.

---

## By the Numbers

| Metric | Value |
| --- | --- |
| Roles | **3** (Hunter, Outfitter, Admin) + dual-role support |
| Total Dart source files (`lib/`) | **246** |
| Named screen files | **58** |
| Distinct UI surfaces (Scaffold-based) | **63** |
| Hunter dashboard feature modules | **22** |
| Outfitter dashboard feature cards | **12** |
| Firestore collections / secured paths | **40+** |
| SA Game Guide species (with photos) | **150** species / **153** bundled images |
| Factory ammunition profiles (bundled) | **~300** loads across **~40** calibres |
| Automated test files | **138** (2,052 tests) |
| Core product version | v1.0.11+13 |

---

## Hunter Side — Detailed Features

### 1. Onboarding, Login & Identity
- **Sign in your way** — email & password or one-tap **Google Sign-In**.
- **Email verification** keeps accounts secure, with a friendly resend flow and a "use a different account" escape hatch.
- **Choose your path** — a clean role-selection screen sends you straight to Hunter mode or Outfitter mode.
- **Password reset** delivered as a fast in-app deep link (not a slow web form), with a built-in 60-second cooldown so you never spam yourself with duplicate reset emails.
- **Password autofill** — the phone's credential manager offers to save your login automatically.
- **Google Play demo reviewer access** — a dedicated review login lets store reviewers explore every restricted feature instantly.
- **Benefit:** *Get into the veld faster. One tap to sign in, a verified account, and the right dashboard the moment you arrive.*

### 2. Hunter Dashboard — Your Field Command Centre
- A branded, mode-aware ("HUNTER MODE") dashboard with a live **SYSTEM ACTIVE** status bar confirming GPS link and module readiness.
- **Collapsible folders** keep the growing toolkit tidy:
  - **All Things Guns** — Digital Firearm Safe + Ammunition Manager.
  - **Market Place** — Package Marketplace, Custom Package Builder, Trophy Registry & Booking.
  - **Tools** — Ballistic Calculator, Field Estimate Verification, Track (Spoor) Identifier, Scope Settings & Tools, Shot Group Target Analyzer.
- **More Modules** below the folders: Weather & Wind Tracker, SA Game Guide, Digital Trophy Room, Off-Grid Mesh Sync, Slaughterhouse Carcass Matrix, Off-Grid Topographic Map, SAPS Tracker, Subscription, Report Bug, Suggest New Feature.
- Favourite features rise to the top, and a **trial banner** shows days remaining in the free trial.
- **Benefit:** *Every hunting tool you own, organised into folders, one tap away — no menus to dig through in the field.*

### 3. SAPS License & Competency Tracker ⭐ (flagship feature)
- **Track your firearm licence live — from the District Office (DFO) all the way to the Central Firearms Register (CFR)** — directly inside the app.
- **Live CFR enquiry:** enter a reference number (and serial for firearm applications) and query the official SAPS portal in real time.
- **Manual refresh** for any single application, or refresh-all in one tap.
- **Full status timeline** with a clear 4-stage progress bar: **At District Office → Provincial → At Central Registry (CFR) → Printing & Collection**.
- **Plain-language guidance** for each stage — what is happening and what comes next, with an estimated waiting period per stage.
- **Working-day tallies** that count only genuine South African working days (weekends and public holidays automatically excluded) — "N workdays since submission", "N workdays at provincial DFO".
- **Complete firearm details captured and displayed:** make/brand, calibre, serial number and application number (e.g. a live example: **HOWA · .338 WIN MAG · s/n F004574 · app 10654672 · status date 09 Oct 2026**).
- **SMS smart-paste:** paste the SAPS SMS and the app extracts the reference, make, calibre, serial and status for you — no manual typing.
- **Batch and status metadata** surfaced per application (batch number, submission date, portal status date).
- **Approved-to-Safe shortcut:** when a licence is approved, one tap adds the firearm straight into your Digital Firearm Safe.
- **Application tracking** across Section 13 (self-defence), Section 15 (occasional sport) and **Section 16 (Dedicated Hunting)**, plus Competency Certificates.
- **Benefit:** *Stop phoning the DFO. Watch your licence move stage-by-stage, see exactly how long it has been waiting, and know what happens next — with your firearm's full details on one card.*

### 4. Digital Firearm Safe ("All Things Guns")
- **Manage your rifle licences** in a single, secure digital safe.
- Each firearm card shows make, model, calibre, serial and **licence status (VALID / EXPIRED)**, with a live barrel-life tracker.
- **Quick actions** per firearm: log rounds fired, schedule maintenance, renew when expiring.
- **Edit make / model / caliber / serial** on the spot, from the safe or the detail view.
- **Licence scanner** — scan a SA licence PDF417 barcode with the camera to auto-fill details.
- **Firearm renewal** flow.
- Photos per firearm for visual inventory.
- **Benefit:** *Every firearm, licence and round count in one place — know what is valid, what needs renewing, and what is due for maintenance.*

### 5. Ammunition Manager
- **Factory ammunition** and **custom handloads** side by side.
- Cascading brand → grain → description selector, backed by a bundled catalogue of **~300 factory loads** across **~40 calibres** that works even with no internet.
- Custom load recipes with bullet, propellant, and velocity data.
- Linked to the Ballistic Calculator so your load data feeds your drop calculations.
- **Benefit:** *Never wonder which load you last used. Factory ammo and your own recipes, organised by calibre and ready for the range.*

### 6. Ballistics & Precision Tools
- **Ballistic Calculator** — bullet drop, velocity and energy over range, with G1/G7 drag models, ICAO atmosphere (altitude, temperature, pressure, humidity), powder-temperature muzzle-velocity correction, **density altitude**, and interactive trajectory charts.
- **Scope Settings & Tools** — configure reticle, turrets, click values, focal plane and parallax; link the profile to a firearm in your safe; audit history of every optic save.
- **Shot Group Target Analyzer** — photograph a target, calibrate scale against a coin or 1-inch grid, and get true **extreme spread, mean radius and center of impact** in MOA/MIL, plus a suggested turret correction; save target sessions to your log.
- **Field Estimate Verification** — estimate horn length using visual ear-to-horn ratios, benchmarked against official Rowland Ward minimums.
- **Benefit:** *Dial in confidence. Real ballistics, real atmosphere, real target analysis — the numbers that put shots on the mark.*

### 7. Track (Spoor) Identifier
- **Scan a footprint with your camera** and let on-device AI match it to a species and morphological category (paw/carnivore, cloven-hoofed/ungulate, solid hoof/equine).
- Scale-reference calibration for accurate sizing, contour analysis, and GPS logging of every scan.
- Works **fully on-device** (no signal required).
- **Benefit:** *Know what walked past your blind. Point, scan, and identify the spoor in seconds.*

### 8. SA Game Guide & Field Data
- **150 South African game species** with photos, profiles and scientific names — browsable by category (Big Game, Plains Game, Predator, Bird) and searchable.
- **Rowland Ward minimum trophy standards** and measurement guidance per species.
- **Offline-capable** — species profiles and photos are bundled and cached.
- **Benefit:** *A pocket field guide for every stalk, with the trophy standards you actually need for judging before you shoot.*

### 9. Digital Trophy Room
- **Log every hunt and trophy** with photos, measurements, date, location and notes.
- Rich **photo galleries** per trophy with full-screen viewing.
- **Share a harvest** to WhatsApp, email, SMS or any installed app — the trophy photo goes with the caption automatically.
- Field estimate and sighting logging.
- **Benefit:** *Your trophies, remembered properly — with the photos, the measurements and the story, ready to share.*

### 10. Marketplace (Hunter)
- **Package Marketplace** — browse and book hunting packages from verified outfitters, filtered by province; each package shows real photos, species, inclusions and price.
- **Custom Package Builder** — pick a farm, choose dates and party size, select species and lodging, and send a custom request to the outfitter.
- **Trophy Registry & Booking** — browse saleable trophy stock from outfitters and book the animal directly.
- **Real-time availability strip** that shows available vs. blocked dates (respecting the outfitter's calendar or manual blackouts).
- **Booking lifecycle you can follow:** Pending Approval → Awaiting Payment → Confirmed → Completed, with in-app status badges.
- **Outfitter contact card** on every package so you can reach the right person directly.
- **Add Hunt to Calendar** — save confirmed hunt dates, farm and package details straight into your phone's calendar.
- **Benefit:** *Find the hunt, build the hunt, book the hunt — then keep the dates in your calendar and the outfitter one tap away.*

### 11. Off-Grid Navigation & Maps
- **Off-Grid Topographic Map** — OpenTopoMap contour tiles cached to your device for complete offline navigation; pre-download any area before you leave.
- **Trail path tracing** with GPS waypoints.
- **Off-Grid Mesh Sync** — P2P Bluetooth team radar and telemetry, so your party stays in touch with no cell service at all.
- **Emergency / team coordination** across nearby devices.
- **Benefit:** *Go where there is no signal — and still navigate, waypoint and stay connected with your team.*

### 12. Field & Slaughterhouse Logistics
- **Slaughterhouse Carcass Matrix** — track hanging game, cold-storage positions, and field-to-hanging weight ratios.
- **Meat processing** orders and order history.
- **Carcass logging** with butchery markup.
- **Weather & Wind Tracker** — live wind direction, forecasts and solunar (sun/moon) cycles for planning the stalk.
- **Benefit:** *From the shot to the cold room — the whole meat-handling chain tracked to the kilogram.*

### 13. Hunting Compliance Documents
- **Venison Transport Permit** — the official SA game transport & hunt permit, issued with both parties' digital signatures and exported as a branded PDF, ready for road-side checks.
- Permit log for hunters to view issued permits.
- **Benefit:** *Legal paperwork, done in the app and signed on the glass — with a PDF you can show anywhere.*

### 14. Profile, Settings & Support
- **Hunter Profile** with personal, contact and farm details; a mandatory-onboarding gate ensures new hunters complete their profile before booking.
- **Privacy & data controls** (POPIA-compliant) with in-app privacy policy and an explicit **Delete My Account & Data** option.
- **Day / Night theme** toggle for bright sunlight or low light.
- **Change password** and prominent **Logout**.
- **Report Bug** — attach up to 5 screenshots plus device diagnostics, and optionally hand off to support email.
- **Suggest New Feature** — send product ideas straight to the team.
- **Benefit:** *Your data, your way — with a support line that actually captures the problem and the screenshot.*

### 15. Subscription & Trial (Hunter)
- **30-day free trial** on sign-up, automatically provisioned.
- **Google Play Billing** subscriptions — Hunter tier at **R34.99/month** (VAT-inclusive), cancel/manage via Google Play.
- Global **forced-update** gate so users are protected from outdated builds.
- **Benefit:** *Try everything free for 30 days, then a fair monthly price with Play Store billing you already trust.*

---

## Outfitter Side — Detailed Features

### 1. Outfitter Dashboard
- A distinct "OUTFITTER MODE" dashboard (with "FARM MANAGER MODE" for assigned managers) over the branded bushveld background.
- **12 feature cards** grouped by workflow, with a mode switcher for dual-role/admin accounts.
- FARM MANAGEMENT HUD for managers shows the tools a farm manager needs.
- **Benefit:** *One control panel for the whole operation — farms, stock, packages, bookings and money.*

### 2. Farm & Manager Management
- **Manage Farms & Managers** — register farms and concessions with name, province, district, size, contact and registration details.
- **Assign farm managers** to specific properties with their contact details.
- Farm photo upload and per-farm cost-rate configuration (daily rate, accommodation, catering, vehicle, guide).
- **Booking & ERP Sync** — connect each farm to a manual date block-out, an external **iCal calendar feed**, or a built-in mock simulator, with a one-tap **Test Connection**.
- Per-farm **PayFast payout profile** so hunter deposits route to the correct farm account.
- **Benefit:** *Register every farm and manager, set their costs and calendars, and let the platform route payments correctly.*

### 3. Trophy Stock Inventory
- **Manage saleable trophy stock per farm** — species, available quantity, price per trophy, measurement, and photos.
- Full CRUD with inline edit and delete, and restock when a species sells out.
- Grouped "Current Stock by Farm" view with per-farm totals and species breakdowns.
- **Trophy Inventory Report** exported as a branded PDF.
- **Benefit:** *Know exactly what is on the farm and what it is worth — and turn that inventory into bookable listings.*

### 4. Price Lists
- **Per-farm price lists** — species, gender, horn/tusk length, quantity and price.
- **Itemised service rates** — the nine standard farm service categories (vehicle, big/small slaughtering, coldroom, hunter daily, observer daily, overnight accommodation ×2, catering), each with clear unit semantics ("per vehicle per day", "per night", "per animal").
- **CSV import** for bulk price loading, and a branded **Price List PDF** export that omits zero/blank line items.
- **Benefit:** *Publish a clean, professional price list once — the platform does the maths and the hunters do the rest.*

### 5. Package Publishing & Management
- **Publish Hunting Package** — all-inclusive or itemised pricing, the seven standard itemised line items, multi-species selection from the SA Game Guide, availability date window, inclusions, deposit percentage, and up to 5 gallery photos (camera or gallery).
- **Manage My Packages** — activate, draft, archive, edit or delete listings; see remaining slots and status at a glance.
- **Automatic sold-out handling** — the last slot decrements the count and flips the package to SOLD OUT.
- **Benefit:** *Build a beautiful, bookable hunting package in minutes and manage its full lifecycle from one screen.*

### 6. Incoming Booking Requests
- **Review and approve or decline** hunter booking transactions.
- **Active Requests vs. Archived** tabs, with **category filters** (Standard / Custom / Trophy).
- **Verify/Confirm Payment Received** to move a booking to Confirmed once off-platform payment lands.
- Chat-free, direct contact: hunter contact details (name, phone, email) shown on every booking.
- **Add Hunt to Calendar** to save confirmed hunts.
- **Benefit:** *See every request, approve in a tap, and confirm payment when it arrives — with the hunter's contact details right there.*

### 7. Client & Hunt Management
- Roster and booking records per hunter, with ID/passport, nationality and contact capture.
- Harvest logging tied to the venue, species and trophy measurement.
- Client booking records for lodge, vehicle and fleet assets.
- **Benefit:** *A clean client book and harvest record you can rely on season after season.*

### 8. Venison Permit Log & Manager
- **Issue, view, search and manage venison transport permits** in one place.
- Both parties sign on the screen; permits export as branded PDFs.
- Void and delete actions with the dual-partition (outfitter/hunter) record.
- **Benefit:** *Compliant transport permits, signed and stored, ready for any roadside check.*

### 9. Business Intelligence & Financial Tools
- **Financial Revenue Summary** — gross earnings and net disbursed revenue, monthly trends.
- **Income per Farm**, **Species Revenue Breakdown**, **Farm Revenue Breakdown**.
- Revenue analytics **PDF report** with farm-grouped breakdowns and a manager directory.
- Never counts unverified bookings — only confirmed and completed work counts toward revenue.
- **Benefit:** *Real numbers on real work — see what each farm and species actually earns.*

### 10. Outfitter Subscription
- **Google Play Billing** Outfitter tier at **R299.99/month** (VAT-inclusive), with the same 30-day free trial.
- **Benefit:** *Predictable monthly billing with a free trial to prove the value.*

### 11. Profile, Verification & Account
- Enterprise profile (business name, province, contact) readable by hunters in the marketplace.
- Outfitter settings sheet with privacy policy and a full **Delete Account & All Data** (GDPR/POPIA) cascade.
- Report Bug / Suggest Feature for outfitter-specific feedback.
- **Benefit:** *A verified, discoverable business profile with full data control.*

---

## Shared Platform Features

- **Authentication & Identity** — email/password, Google Sign-In, email verification, password reset, and a dual-role/admin mode switcher.
- **Role-Based Access Control** — every route is guarded; hunters cannot open outfitter or admin surfaces and vice-versa; admins have cross-mode access.
- **Cloud Firestore** — real-time sync of bookings, applications, packages, permits and logs.
- **Cloud Storage** — photos for firearms, trophies, packages, farms, bug reports and signatures.
- **Push Notifications (FCM)** — booking status changes, package updates and new requests, with local-notification display.
- **Firebase Analytics & Crashlytics** — usage tracking and crash reporting.
- **Firebase App Check** — Play Integrity (Android) and App Attest (iOS) in release builds to protect backend resources.
- **Remote Config force-update kill switch** — server-controlled minimum version gate to protect users from outdated builds.
- **Offline support** — Firestore persistence, disk-cached map tiles, offline species/ammunition data, and an offline write queue that syncs on reconnect.
- **SQLite local persistence** — offline harvest/carcass logs and target sessions.
- **Referral programme** — share a code, earn a reward; App Links on `jag-spoor.co.za/r/<CODE>` plus a `jagspoor://` fallback, with a web landing page.
- **On-device image compression** — uploads are compressed before leaving the phone.
- **POPIA privacy compliance** — sensitive data isolation, in-app policy, and account deletion.
- **Day/Night theming, adaptive layouts and safe-area handling** across the whole app.

---

## Technical Highlights for Marketing

- **Live SAPS CFR integration.** The tracker queries the official SAPS firearm-status portal in real time (reference + serial), classifies the raw portal phrase into the correct stage, and renders a full timeline — this is a genuinely differentiated capability that no generic hunting app offers.
- **Offline-first architecture.** Firestore caching, a disk-persistent topo-tile store, bundled species and ammunition catalogues, and an offline write queue mean the app is fully usable in areas with no signal.
- **Off-grid P2P mesh.** Bluetooth peer-to-peer team radar and telemetry let groups coordinate beyond any cell network.
- **On-device AI.** TensorFlow Lite / LiteRT powers spoor identification without sending data to the cloud.
- **Real ballistics engine.** Drag-curve-aware trajectory integration with ICAO atmosphere and density altitude.
- **Instant, offline factory-ammunition catalogue.** ~300 loads across ~40 calibres bundled and indexed for offline selection.
- **16 KB page-size ready** for modern Android (Play requirement compliant).
- **Firebase-native.** Auth, Firestore, Storage, Messaging, Analytics, Crashlytics, Remote Config, App Check.
- **Tested at scale.** 138 test files and 2,052 automated tests back the release.

---

## Current Version Status — v1.0.11+13

- **Product version:** 1.0.11+13 (build 13).
- **Channels:** Google Play (Android) and iOS.
- **Subscription pricing:** Hunter R34.99/month, Outfitter R299.99/month (both VAT-inclusive), 30-day free trial.
- **Recently shipped highlights:** live SAPS CFR tracker with status timeline and working-day tallies; a cleaned-up hunter dashboard; the dual-role Google Play demo-reviewer experience; the pricing/referral model; and the Firebase project hardening (rules, indexes, storage).

*(Note: the `pubspec.yaml` / Android manifest currently in the tree read `1.0.10+10`; the v1.0.11+13 label is the target release referenced in the product brief and should be reconciled in the version files at the next build.)*

---

## Unique Selling Points for Marketing

1. **The only app that tracks your SAPS firearm licence live — from DFO to CFR to collection.** Enter a reference, watch the status move, see the working-day count and exactly what happens next.
2. **Everything a hunter needs in one app — not five.** Licence tracking, firearm safe, ammunition, ballistics, spoor AI, species guide, maps, trophy room and marketplace together.
3. **Built for the bushveld: it works offline and off-grid.** Cache maps, read species data, log trophies and coordinate your team with zero signal.
4. **A genuine two-sided marketplace.** Hunters discover and book real packages from verified outfitters; outfitters get a full farm-management and sales platform in the same app.
5. **Real ballistics, not guesswork.** G1/G7 drag models, ICAO atmosphere, density altitude and target group analysis in MOA/MIL.
6. **AI in your pocket.** Snap a track and identify the species on-device.
7. **A shareable digital trophy room.** Log, measure and broadcast your harvest with the photo attached.
8. **Enterprise tools for outfitters.** Farms, managers, price lists, trophy stock, packages, bookings, permits and revenue analytics.
9. **Compliance made easy.** Signed venison transport permits and POPIA-compliant data handling.
10. **Trusted billing.** Google Play subscriptions with a 30-day free trial.
11. **Deep South African focus.** ZAR pricing, SAPS workflows, SA public-holiday-aware working days, Rowland Ward standards and SA game species.

---

## Future Roadmap Placeholders

The source tree does not contain a formal public roadmap, but the following in-code markers and open threads are candidates to explore or communicate:

- **Deferred on-device deployments** — the SAPS CFR scraper supports both a deployed webhook (production path) and a direct on-device portal enquiry; the production webhook/actor deployment is the remaining ops step.
- **Firestore rules / indexes / storage deployment** — several hardening changes (referral codes, purchases, partitioned permits, storage scopes) are committed and awaiting a credentialed `firebase deploy`.
- **Legacy data migrations** — one-time migrations are noted for legacy venue/trophy/booking documents as the schema has evolved.
- **Opt-in analytics expansion** — the admin portal already tracks feature usage by role; broader engagement analytics are a natural extension.
- **Additional marketplace payment/verification flows** — the off-platform (direct) booking and payment-verification state machine is live; automated verification could extend it further.
- **More field modules** — the modular dashboard architecture is built to accept new "Tools" and "More Modules" cards quickly.

---

*Prepared read-only from `main` @ `8b0d641`. Contains no code changes — marketing copy and feature inventory only.*
