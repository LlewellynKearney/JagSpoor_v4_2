JagSpoor - TODO (International Hunters + Services)
Last updated: 2026-10-12
Status: SPEC ONLY - DO NOT BUILD YET

1. ALREADY POSTED - International Hunter Side (from yesterday)
Goal
International Hunter is just a role (UserRole) like hunter/outfitter/butchery/taxidermy - not a separate app or profile type. Same base user, different role flag.

Features
 Add UserRole.internationalHunter to roles enum (alongside hunter, outfitter, butchery, taxidermy, admin) - just a role
 Onboarding fields for this role: passport no, country, firearm import docs (SAPS 520), home outfitter linkage
 Document vault (role-gated): upload SAPS, customs, flight details - encrypted storage
 Outfitter matching: role internationalHunter can search SA outfitters, see packages, trophy pricing (same UI as hunter)
 Currency toggle: ZAR / USD / EUR - auto convert pricing (role preference)
 Trip planner: dates, species wishlist, travel checklist
 Compliance: SAPS 520 auto-fill from profile + trip
 Chat with outfitter + translator helper
Firestore (role-based, not separate collection)
users/{uid} { role: "internationalHunter", ...existing hunter fields + passport, country }
users/{uid}/documents/{docId} (or internationalDocs subcollection)
trips/{tripId} { hunterId, outfitterId, dates, species[], status } - hunterId can have role internationalHunter
All existing hunter logic reused - just check role == internationalHunter for extra fields
CRITICAL - Local vs International Separation (JagSpoor Rule)
Problem: International hunters drive prices up, local cannot afford. JagSpoor must cater SEPARATELY.

Solution - Optimum Outfitter must solve before they ask:

1. Separate Pricing Pools (No Mixing)
outfitters/{uid}/packages/{packageId} has audience: local | international | both
outfitters/{uid}/pricing/trophyFees/{species} has localPrice and intlPrice (ZAR & USD)
Hunter role filter:
role == hunter -> ONLY sees audience == local + localPrice + ZAR
role == internationalHunter -> ONLY sees audience == international + intlPrice + USD/EUR/ZAR toggle
Outfitter dashboard: 2 tabs - Local Hunts and International Safaris - separate inventory
Search: FindOutfitterScreen queries where audience in [roleAudience, both]
Booking: bookings stores audience to enforce correct pricing
Rule: Never show international pricing to local hunter. Never show local pricing to international (prevents price shock both ways)
2. Optimum Outfitter Gold Standard Checklist (Must-Have to be Featured)
Outfitter profile has goldStandardScore 0-10, calculated from:

a) Legal & Professional Foundation (Weight: Critical)

 Fully licensed outfitter + PH license no (verified)
 PHASA / SAPA membership badge
 English-fluent, first-aid trained PH
 Paperwork service: invitation letter, SAPS 520 pre-approval, TOPS/CITES, vet/export docs - auto-checklist in app
 Insurance + emergency plan: medevac, nearest hospital, sat comms
 No grey areas: pricing transparency, no guaranteed trophies wording (American hunters flag this)
b) Hunting Area & Game

 Concession size: 10,000+ acres minimum (Limpopo/NW model) - field concessionSizeAcres
 Fair chase, mature trophies - not put-and-take
 Variety: wishlist species + culls/management at reduced fees
 Ratio: 2:1 or 1:1 PH:hunter, with tracker, skinner, vehicle included
c) Logistics - First Impression

 Meet-and-greet at OR Tambo + firearm customs help (critical for satisfaction)
 Transfers, charter flights, malaria-free badge is huge selling point for SA
 Pre-safari pack in app: what to bring, calibre advice, visa, clothing (German/Spanish expect hard stalking - prepare them)
d) Accommodation - Varies By Nationality

 Spanish expect higher standard than Americans - more effort from hosts
 Optimum: thatched 5-star chalet, en-suite, laundry, stable power, WiFi, gun safe, good beds
 Photos: clean lodge with lots of photos signals pride
e) Food & Hospitality

 SA cuisine, game dishes, SA wines/beers + dietary options
 German hunters highest expectations here
 Campfire time not optional - want to share with like-minded
f) Guiding & Equipment

 Knowledgeable hard-working guide
 Well-maintained trucks, radios, sticks, recovery equipment
 Good skinning shed + cold room
g) Trophy Care - Most Overlooked Deal Breaker

 Immediate field prep, caping, salting, tagging with photos
 On-site or partnered taxidermy (link to taxidermy role in app)
 Full dip-and-pack + shipping quotes upfront - Germans fear overcharging
 Integration: booking auto-creates butchery/taxidermy booking
h) Transparency in Pricing

 All-inclusive daily rate + trophy fee model - contract states:
Included: accommodation, meals, drinks, PH, tracker, skinner, field prep, laundry, airport transfer
Extra: trophy fees, dip/pack, flights, taxidermy freight, gratuities, wound-and-pay policy
 No hidden costs UI in app
i) Conservation & Story

 How fees fund anti-poaching, community jobs (Americans link hunting to conservation)
 Community visit options (Spanish want to learn about SA)
 Sustainable use data
j) Non-Hunting Program

 Observers/spouses: photo drives, cultural tours, fishing, spa - competitive for US groups bringing family
Implementation:

outfitters/{uid}/goldStandard { checklist map, score, verifiedDocs[] }
Featured list: only outfitters with score >= 8 shown to international hunters by default
Local hunters see all local outfitters (price sensitive)
International hunters see gold standard first
2. NEW - Butchery & Taxidermy Profiles (ADDED TODAY - SPEC ONLY)
Goal
Build 2 more roles just like International Hunter: BUTCHERY and TAXIDERMY - all 5 roles use same UserRole enum.

2a. Roles (all just roles)
enum UserRole { hunter, internationalHunter, outfitter, butchery, taxidermy, admin }
All roles share users/{uid} base doc with role field
No separate apps - just role flag + role-specific onboarding + dashboard
Onboarding: business name, location (lat/lng), service area radius km, contact, license no (role-gated)
Dashboard for each
2b. Butchery - Pricing Management (Local vs International Separation Applies)
Must be able to load/manage service pricing:
Services: Skinning, Cutting, Vacuum Pack, Sausage, Biltong, Mince, Dry Wors, etc.
Model: name, category, localPrice + intlPrice, priceUnit (perKg/perAnimal/fixed), audience: local|international|both, species (optional), turnaroundDays, notes, active
Screen: ButcheryPricingScreen (CRUD) - 2 tabs: Local Services | International (Dip/Pack/Export)
Firestore: butcheries/{uid}/pricing/{serviceId} { localPrice, intlPrice, audience, ... }
Separation:
hunter sees only localPrice (ZAR) - biltong, sausage, mince pricing
internationalHunter sees only intlPrice (USD) - dip/pack, export prep, veterinary, shipping crates - must be upfront (Germans fear hidden costs)
Availability + service area
2c. Taxidermy - Pricing Management (Local vs International Separation Applies - CRITICAL)
Must be able to load/manage service pricing:
Mount types: Shoulder, Full mount, Skull, Rug, Flat skin, Pedestal, etc.
Model: name, species, localPrice + intlPrice (ZAR + USD), deposit, audience, turnaroundMonths, portfolioImages[], active, includesDipPack, shippingQuoteType
Screen: TaxidermyPricingScreen - 2 tabs: Local | International Export
Firestore: taxidermists/{uid}/pricing/{serviceId} { localPrice, intlPrice, audience, ... }
Taxidermy Gold Standard Checklist (International):
 Immediate field prep liaison: caping, salting, tagging with photos from outfitter
 Dip-and-pack service included or partnered - full quote upfront (most overlooked deal breaker)
 CITES/TOPS permits handling + veterinary certificates
 Crating + shipping quotes upfront (USD) - no hidden costs
 Portfolio: high-res before/after, species specific
 Turnaround transparency: 8-12 months typical - show timeline
 Insurance for trophies in transit
 Partnership badge: linked outfitters who trust them
Separation:
Local hunter: sees shoulder mount R4500, skull mount R1200, etc. (ZAR, local collection)
International hunter: sees shoulder mount $850 + $250 dip/pack + shipping estimate (USD) - all-in price shown
Rule: Never show international export pricing to local - never show local-only pricing to international
2d. Hunter Side - Search & Book (Domestic + International)
Search nearby butchery/taxidermy:
Use geolocator + geo query (geohash)
Screens: FindButcheryScreen / FindTaxidermyScreen
Filters: distance slider, rating, price range, availability
View: Map (flutter_map) + List sorted by distance
See loaded pricing: when hunter taps provider, show full pricing table + calculator (qty * price)
Book it:
Select service(s) -> qty (kg / nr animals) -> requested date -> notes / trophy tag no
Create: bookings/{id} { hunterId, providerId, providerType: butchery|taxidermy, services[], estimatedTotal, status: pending/confirmed/completed, hunterLocation }
FCM notification to provider
Provider can accept/decline + set final price
Booking history both sides
Works for international hunters too (same flow, adds trip linkage)
Data Model
enum ProviderType { butchery, taxidermy }
enum PriceUnit { perKg, perAnimal, fixed }
enum Audience { local, international, both }
class ServicePricing {
  String id;
  String name;
  String category;
  double localPrice; // ZAR - for local hunter
  double intlPrice; // USD - for international hunter
  PriceUnit unit;
  Audience audience;
  String? species;
  int turnaroundDays;
  String? notes;
  bool active;
  List<String>? portfolioImages; // taxidermy
  bool? includesDipPack; // taxidermy
  String? shippingQuoteType; // taxidermy
}
class Booking {
  String id;
  String hunterId;
  String providerId;
  ProviderType providerType;
  List<BookingItem> items;
  double estimatedTotal;
  Audience audience; // local or international - determines pricing
  String currency; // ZAR or USD
  DateTime requestedDate;
  BookingStatus status;
  GeoPoint? hunterLocation;
  String? tripId; // link to international trip if applicable
}
Acceptance Criteria (for future build)
 Butchery CRUD pricing
 Taxidermy CRUD pricing + portfolio
 Hunter search nearby (within X km) butcheries & taxidermists - works offline cache?
 Hunter sees pricing before booking
 Booking creates notification + provider dashboard entry
 International hunter can also search/book (with tripId)
 Security rules updated for butcheries, taxidermists, bookings
 Tests for pricing + booking
Payments - Monthly Subscription (All Roles)
 Subscription model for ALL roles - same modal, different prices:
hunter: existing local hunter subscription (keep current price)
internationalHunter: same modal/flow as hunter, different price tier (higher - USD based)
outfitter: provider plan (existing)
butchery: provider plan
taxidermy: provider plan
 Plans structure - FINAL PRICES (per month):
hunter: R34.99/mo (ZAR)
internationalHunter: $5.99/mo (USD) - same modal/flow as local hunter, different price
outfitter: R299.99/mo (ZAR)
butchery: R149.99/mo (ZAR)
taxidermy: R149.99/mo (ZAR)
Billing: Google Play Billing (existing BILLING permission) + RevenueCat / Stripe for web - reuse current billing implementation
Same paywall modal/widget for all roles - just pass UserRole to get price/currency
Google Play Console: create 5 subscription products: hunter_monthly, intl_hunter_monthly, outfitter_monthly, butchery_monthly, taxidermy_monthly
 Firestore: subscriptions/{uid} { role, plan, price: 34.99|5.99|299.99|149.99, currency: ZAR|USD, status: active/trialing/past_due/canceled, currentPeriodEnd, providerType }
 Gate:
Hunters (local + international): gate trophy log, hunt search, booking, document vault behind active sub
Providers (outfitter/butchery/taxidermy): gate pricing CRUD & receiving bookings behind active sub
 Check subscription on dashboard load -> if inactive, show paywall modal (same modal as hunter)
 Free trial 14 days for new butchery/taxidermy + internationalHunter
 Webhook handling for renewals/cancellations (Cloud Functions)
 Hunter still pays provider directly offline - subscription is app access fee only
Out of scope (later)
In-app chat (reuse existing)
Reviews v2
Hunter-to-provider payment (handled offline)
3. IMPLEMENTATION PLAN - MINIMAL CHANGE (How to incorporate without breaking current JagSpoor v4_2)
Principle: Extend, don't replace. All new fields nullable with defaults.
Phase 1 - Non-breaking extension (1-2 days when build starts)
A. Roles (reuse existing)

Current: enum UserRole { hunter, outfitter, admin }
New: enum UserRole { hunter, internationalHunter, outfitter, butchery, taxidermy, admin }
Existing checks role == hunter still work
New logic: if role == internationalHunter -> show passport, SAPS 520, currency toggle
Firestore: no migration needed - new users get new role, old users unchanged
B. Pricing Model - Extend, not replace (backward compatible)

// Existing model keeps working
class Package {
  double? price; // OLD - keep for compat, nullable
  double? localPrice; // NEW - if null, fallback to price
  double? intlPrice; // NEW - if null, hide from international hunters
  Audience audience; // NEW - default Audience.both so existing packages show to all
}
// Migration on read:
double get effectiveLocalPrice => localPrice ?? price ?? 0;
double get effectiveIntlPrice => intlPrice ?? price ?? 0;
Outfitter dashboard: add 2 price fields + Audience chips [All | Local | International] on top of existing screen
Existing outfitters: audience = both by default -> no breaking change
C. Outfitter Gold Standard - Just a badge

New: outfitters/{uid}/goldStandard { checklist: Map, score: int, verifiedDocs: [] }
UI: collapsible section in existing outfitter onboarding: Optimum Outfitter Checklist (10 items)
Scoring: score = checkedCount / 10
Sorting only, no filtering: international hunters sorted by score desc, local hunters sorted by distance/price
Featured badge: Gold Standard if score >= 8
D. Subscription - Reuse same modal

Existing modal widget: SubscriptionPaywallModal
Pass UserRole -> returns price:
hunter: R34.99
internationalHunter: $5.99
outfitter: R299.99
butchery/taxidermy: R149.99
Play Console: create 5 products: hunter_monthly, intl_hunter_monthly, outfitter_monthly, butchery_monthly, taxidermy_monthly
Gate same as before: dashboard load checks subscriptions/{uid}.status == active
Phase 2 - Adapt Gold Standard INTO Local Hunter (feels like upgrade, not change)
Gold Standard Feature	How to adapt to Local Hunter (minimal)
Trophy Care (deal breaker)	In existing Trophy Log, add button Find Taxidermy / Butchery Nearby -> reuses Find screens. Local hunters lose trophies to bad caping too.
Transparency Pricing	Existing package view: add 2 bullet lists: Included: ... and Extra: ... (daily rate + trophy fee). Local hates hidden costs too.
Pre-hunt pack / Logistics	Reuse Trip Planner: for local, show Farm gate GPS, check-in, what to bring, calibre advice instead of OR Tambo. Same widget, different text per audience.
Accommodation photos	Outfitters already upload lodge photos. Require 5+ photos to get Verified Lodge badge - works for both.
Conservation story	Add optional field conservationImpact to outfitter profile - show for both, international sees first.
Food & hospitality	Existing lodge description - add tags: Traditional SA cuisine, Boma, Laundry, etc.
Phase 3 - Butchery/Taxidermy Reuse Outfitter UI (0.5-1 day)
Butchery/Taxidermy dashboard = clone of Outfitter dashboard pricing CRUD (same widget, different labels)
Hunter search: clone FindOutfitterScreen -> FindButcheryScreen + FindTaxidermyScreen (same map+list, query where role == butchery)
Booking: reuse existing bookings collection, add providerType + audience + currency
No new backend - all existing Firebase rules + FCM notifications reused
Result - No Breaking Changes
Local hunter (R34.99): same app + nearby butchery/taxidermy + transparent pricing + trophy care button = feels like upgrade
International hunter ($5.99): sees USD pricing, gold standard sorted, OR Tambo, dip/pack quotes upfront, SAPS 520 handling
Outfitter (R299.99): sets 2 prices once, gets both markets separately - solves price inflation
Butchery/Taxidermy (R149.99): same dashboard, 2 tabs Local/International
Code change: ~5 new files, 3 modified files (UserRole enum, Package model, Outfitter dashboard)
Build Order When Requested
 Extend UserRole + Package model (nullable fields, default both) - 2 hours
 Outfitter dashboard 2 price fields + audience chips - 3 hours
 Gold Standard checklist + badge + score sorting - 3 hours
 Butchery/Taxidermy roles + pricing CRUD (reuse outfitter UI) - 4 hours
 FindButchery/FindTaxidermy screens (clone FindOutfitter) - 3 hours
 Booking with audience + currency + tripId link - 3 hours
 Subscription paywall 5 products - 2 hours
 Tests + security rules
Total: ~20 hours, no breaking changes to existing 1.0.11 build in Play Console review.

4. TODO - New Feature: UV / Fluorescence Overlay for Spoor/Track Identifier (SPEC ONLY)
Goal
Add UV/fluorescence imaging mode to existing Spoor/Track identifier to help hunters identify tracks at night/low-light and detect blood trails, urine markers, and disturbed ground not visible in normal light.

Why it fits JagSpoor
Local hunters track wounded animals at dusk - blood fluoresces differently under UV
International hunters expect tech edge - UV mode is differentiator vs other hunting apps
Reuses existing ML track identifier - just adds camera filter + overlay model
Features (Spec Only - DO NOT BUILD YET)
4a. Camera Modes
 Add toggle in Track Identifier screen: Normal | UV | Fluorescence Overlay
 UV mode: use device camera with blue light filter + increased exposure
 Fluorescence overlay: ML model highlights organic material (blood, urine, broken vegetation) with neon overlay
 Torch integration: if device has UV LED (some rugged phones) - auto enable, else show "Use external UV torch" prompt
4b. Track Enhancement
 Spoor detection: UV highlights fine edges of tracks in dust/mud that normal light misses
 Blood trail mode: separate toggle Blood Trail - enhances red/brown fluorescence, draws path line on screen
 Species-specific UV patterns: some urine/scat fluoresces differently - add to existing species database
 Save UV vs Normal side-by-side comparison image
4c. Model & Data
 Extend existing TFLite model: spoor_identifier.tflite -> add UV training dataset
 New model: uv_fluorescence_overlay.tflite - segmentation model (blood, urine, disturbed ground)
 Training data: night tracking photos + blood trail photos (UV and normal)
 On-device inference - no internet needed in bush (critical)
4d. UI/UX
 Screen: TrackIdentifierScreen - add bottom toggle bar: [Normal][UV][Blood]
 Overlay: semi-transparent neon green for tracks, neon red for blood, neon yellow for urine/disturbance
 Capture: saves both normal + UV image + overlay mask
 Share: include UV image in trophy log / hunt report
 Settings: calibration for external UV torch intensity
4e. Firestore & Storage
 users/{uid}/trackScans/{scanId} { normalImageUrl, uvImageUrl, overlayMaskUrl, mode, speciesGuess, confidence, location, timestamp }
 uvCalibration/{deviceModel} { exposure, filterStrength } - crowd-sourced per device
 Storage: track_scans/{uid}/{scanId}_normal.jpg, _uv.jpg, _overlay.png
4f. Acceptance Criteria (future build)
 Toggle between Normal/UV/Blood modes in Track Identifier - no crash
 UV overlay highlights blood trail visible in low light
 Works offline - on-device TFLite
 Saves side-by-side comparison
 Battery efficient (UV mode drains fast - show warning)
 Tested on 5+ Android devices including rugged (CAT, Samsung XCover)
4g. Subscription Gate
 NO CHARGE - Free for both hunter roles
 Available in hunter (R34.99 sub) AND internationalHunter ($5.99 sub) at no extra cost - included in base subscription
 Also available in free tier: basic UV filter (without ML overlay) - premium ML blood trail overlay requires active sub but no additional charge
 Actually: per requirement - UV fluorescent feature has NO CHARGE - available to both local and international hunter roles even without sub? If must be free for all: remove gate entirely - just include in app
 Final: UV feature = free, included for both hunter and internationalHunter roles - no paywall, no extra charge - core feature
4h. Out of Scope (later)
 Thermal overlay (different hardware)
 Real UV camera hardware integration
 iOS version (Android first)
Implementation - Minimal Change
 Reuse existing TrackIdentifierScreen + camera controller
 Add filter: simple image processing (blue channel boost + contrast) for MVP, ML overlay later
 New file: uv_overlay_service.dart - handles mode switching + inference
 New file: blood_trail_painter.dart - custom painter for neon path
 Modify 1 existing file: track_identifier_screen.dart - add toggle bar
Total: ~8 hours, reuses existing camera + ML pipeline, no breaking changes.

5. TODO - JagSpoor Marketplace (Safari Outdoor killer) - SPEC ONLY - Deepsearch Findings Applied
Deepsearch Summary - Safari Outdoor Failures
Website: single-retailer shop (7 mega stores, 151k visitors/month) - NOT a marketplace
App: 50K+ downloads, 4.6 stars - social + classifieds + SAPS tracker - marketplace broken
Failures: R100 per ad to publish (greed after scammers), links open Play Store not ad, search doesn't return results, Firestore permission-denied on SAPS tracker, credit system killed usage, no testing before release
Opportunity: Build TRUE multi-vendor marketplace - free with sub, deep links work, search works, verified sellers
Goal
Build user-friendly marketplace that works - where hunters sell private gear/firearms, outfitters sell hunts (local vs international separated), butchery/taxidermy sell services - all in one search with trust.

5a. Why Hunters Will Switch from Safari Outdoor
Safari: Pay R100 per ad, pray you sell + links broken + scammers
JagSpoor: Free listings included in R34.99 hunter sub, deep links work, verified sellers, map view, works offline in bush
5b. Roles & What They Can Sell
hunter (R34.99): SELL private gear - rifles, shotguns, optics, ammo (private), clothing, etc. + BUY everything
internationalHunter ($5.99): BUY hunts (international pricing), BUY taxidermy/butchery export services + SELL gear (same as hunter) - sees USD
outfitter (R299.99): SELL hunt packages - 2 tabs Local (ZAR) / International (USD) - audience separated - Gold Standard badge
butchery (R149.99): SELL services - Local tab (biltong, sausage R/kg) / International tab (dip/pack USD) - audience separated
taxidermy (R149.99): SELL mounts - Local (R) / International (USD all-in with dip/pack + shipping estimate) - Gold Standard
Future retailer (R299.99): SELL new retail stock like Safari Outdoor - same audience separation - later phase
5c. Listing Model
enum ListingType { gear, firearm, huntPackage, butcheryService, taxidermyService, retail }
enum Audience { local, international, both }
enum Condition { new, likeNew, good, fair }
class MarketplaceListing {
  String id;
  String sellerId;
  UserRole sellerRole;
  ListingType type;
  Audience audience; // default both - local hunter sees local, international sees international
  String title;
  String description;
  List<String> photoUrls; // compressed + CDN
  double localPrice; // ZAR - nullable
  double intlPrice; // USD - nullable
  String currency; // ZAR or USD based on audience
  Condition? condition; // for gear/firearm
  String? calibre; // for firearm
  String? province;
  GeoPoint? location; // for map view + distance
  String? licenseNo; // firearm - required
  bool verified; // ID + license check
  bool featured; // Gold Standard or paid boost
  String status; // active, sold, expired
  DateTime createdAt;
  int viewCount;
  int saveCount;
}
5d. Firestore
marketplace/{listingId} { ...as above, sellerId, audience, geohash for geo query }
marketplace/{listingId}/offers/{offerId} { buyerId, amount, message, status: pending/accepted/declined }
users/{uid}/savedListings/{listingId} { savedAt }
users/{uid}/verification { idVerified, licenseVerified, verifiedAt, badge }
marketplaceReports/{reportId} { reporterId, listingId, reason: scam/fake/wrong, status }
5e. Search & Discovery - Must Work (Unlike Safari)
 Screen: MarketplaceScreen - 2 views: List + Map (flutter_map) toggle
 Search bar: Algolia / Typesense - instant, typo-tolerant, not Firestore query (fixes Safari search fail)
 Filters:
Category chips: [All, Rifles, Optics, Hunts, Butchery, Taxidermy]
Audience: auto-filter by role - hunter sees local, internationalHunter sees international - manual toggle if both
Distance slider: 5km to 500km + nationwide
Price range slider (ZAR or USD based on role)
Condition, Calibre, Province, Verified only, Gold Standard only
 Sort: Newest, Price low-high, Distance, Popular, Verified first
 Deep links that WORK: https://jagspoor.com/m/{listingId} -> opens app if installed, else web page with listing + button to open in app - test on device (fixes Safari link fail)
 Offline cache: cache last 50 listings, queue new listing when no signal in bush
5f. Listing Flow - Free with Sub (Unlike Safari R100)
 Button: + Sell - choose type
 For gear/firearm: photos (compress), title, description, calibre, condition, province, price (localPrice + optional intlPrice), license no if firearm
 Verification step for firearm: upload license photo - admin or auto-check - badge Verified Seller - prevents scammers (Safari failed here)
 Publish:
If subscriptions/{uid}.status == active: FREE, instant publish
If inactive: 3 free ads/month, else paywall modal - "Subscribe to sell unlimited - R34.99/mo" - NOT R100 per ad
 No credit system - no R100 pray-to-sell
5g. Trust & Safety (Safari Scammer Fix)
 Verified badge: ID verified + firearm license verified (if selling firearm)
 Seller rating: after transaction, buyer rates - shown on profile
 Report: 1 tap report scam/fake - goes to admin queue - auto-hide after 3 reports pending review
 Chat: in-app chat only, phone no hidden until both agree - prevents WhatsApp scammers
 No fake payment: warning banner "Only release firearm after SAPS transfer + payment cleared in YOUR banking app - not screenshot"
 Gold Standard badge for outfitters/taxidermy - score >=8
5h. Offers & Booking
 On listing: Make Offer button -> enters amount + message -> creates offer in offers subcollection
 Seller: Accept/Decline/Counter in app + FCM notification
 For hunt/butchery/taxidermy service: Book button -> goes to existing booking flow with audience + currency (reuse Phase 3)
 For gear/firearm: after accept -> chat opens to arrange meetup/SAPS transfer
5i. Subscription Gate - Free with Existing Subs
 NO EXTRA CHARGE - marketplace included in all roles:
hunter R34.99/mo: unlimited buying + selling gear/firearm + buying hunts/services
internationalHunter $5.99/mo: same - sees USD pricing
outfitter R299.99/mo: unlimited hunt packages (local+intl) + buying gear
butchery/taxidermy R149.99/mo: unlimited services + buying gear
 Free tier: 3 listings + unlimited browsing - paywall after 3
 No R100 per ad - ever
5j. Acceptance Criteria
 Hunter can list rifle with photos + licence + location - free if sub active
 Deep link jagspoor.com/m/{id} opens app directly to listing (tested on 2 devices)
 Search returns correct results - Algolia typo-tolerant (test: "308" finds ".308 Win")
 Map view shows listings within radius - geohash query works
 Audience filter: local hunter sees only local + both, international sees international + both - never mixed pricing
 Verified badge shows after ID check
 Report button hides listing after 3 reports
 Offline: can create listing offline, queues, publishes when online
 No Firestore permission-denied errors - rules tested in staging before prod (lesson from Safari)
5k. Implementation - Minimal Change (Reuse Existing)
 Reuse FindOutfitterScreen map+list widget for marketplace
 Reuse Package model extended with Audience + localPrice/intlPrice (Phase 1)
 Reuse booking flow for service bookings
 New: MarketplaceService - Algolia search + deep link handling
 New: ListingCard widget - photo, title, price (ZAR/USD per role), verified badge, distance
 New: SellScreen - form + photo compress + verification upload
 New: Offer flow + chat
 Security rules: marketplace read if audience matches role, write if owner + verified + sub active (or free quota)
Total: ~16 hours, reuses Phase 1-3, fixes all Safari failures, no extra charge.

NOTES FOR OPENHANDS
DO NOT BUILD NOW - spec only
When build is requested, follow Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 (UV free) -> Phase 5 (Marketplace) -> Phase 6 (NR5) -> Phase 7 (NR9)
All new fields nullable with defaults (audience=both) to keep existing outfitters working
Keep existing international hunter TODO untouched
Gold Standard is sorting/badge, not filter - don't hide existing outfitters from local hunters
UV/Fluorescence feature is Phase 4 - free for both hunter roles - core feature
Marketplace Phase 5 - free with sub - killer feature vs Safari Outdoor - must have working deep links + Algolia search + verification to prevent scammers
Test deep links + search + rules in staging before prod - Safari Outdoor failed because they didn't test
6. NR5: VELDBRAND & POACHING ALERT - Farm Watch Tab (SPEC ONLY)
Status
Date: Nov 2026 | Nr1, Nr6, Nr7 Done | Nr8 WIP | Nr5 & Nr9 Next | Build: Dec 2026, 12h

Problem in SA
1 kudu bull poached = R15k-R50k loss
Fence cut = herd escapes, R100k+ loss
Veldbrand Free State/NW can burn 1000ha in hours
Current: WhatsApp groups, alerts get lost, no GPS, no log for insurance
SAPS rural response slow, farm watch faster
Goal
One-tap alert that works OFFLINE in Kalahari with no signal - justifies R299 outfitter tier (one prevented incident = 50 months paid)

6a. One-Tap Alert Button (OFFLINE FIRST) - Core
 Home screen: 4 big buttons (no typing in bush):
[🔥 VELDBRAND] Fire
[✂ HEINING GESNY] Fence Cut/Poaching
[🔫 STROPERY / SUSPICIOUS PERSON] Suspicious
[🐾 SIEK/DOOIE DIER] Sick/Dead game
 Flow: Tap button -> Auto GPS (even offline, use last known) -> Optional 1-tap photo -> Optional 10s voice note m4a -> Save locally SQLite queue + timestamp -> Auto send when signal returns
 No keyboard needed - critical for bush use
 Firestore: alerts/{id} { type: fire|fence|poaching|sick, farmId, gps, reporterId, reporterName, photos[], voiceUrl, status: open/enRoute/resolved/closed, createdAt, synced }
 Local DB: alerts_queue SQLite - offline first
6b. Broadcast System
 Alert sends to:
Farm owner (FCM push + optional SMS via Twilio R49/mo add-on)
Farm manager
Assigned workers list per farm farms/{farmId}/workers[]
Nearby farms opt-in within 10km radius (geo query)
 Auto WhatsApp intent: "ALERT: [TYPE] at -26.12345, 27.45678 - Farm: Leeuwfontein - Time: 14:32 - By: Jan - Open in JagSpoor: https://jagspoor.com/alert/{id}"
 Push: "🔥 Fire at Leeuwfontein North Camp - 2km from you" - FCM topic per farm
 SMS fallback: optional R49/mo add-on via Twilio for no-data areas
6c. Map View (Offline Maps Critical)
 Farm boundaries: user draws polygon or imports KML farms/{farmId} { boundary: Polygon, name }
 Pins: Red=open, Yellow=en route, Green=resolved - tap pin -> photos, voice, reporter, time, status, action taken
 Offline maps: Download farm area - Mapbox offline or Google offline - store in device
 Layers toggle: boreholes, gates, water points, high-risk fence sections
 Screen: FarmWatchMapScreen - flutter_map + offline tiles
6d. Incident Log & Reports (Insurance Value)
 Every alert = incident report: ID, Type, Date/Time, GPS, Reporter, Photos, Voice, Status, Action taken, Cost (R)
 Filter: by farm, type, date, status
 Export PDF for insurance: "Incident #123 - Fence cut 12 Dec 2026 - Location -26.123,27.456 - Photos - Damage: 200m fence, R4,500 - Reported by Jan" - uses pdf package
 Analytics: "3 fence cuts at North fence in last 30 days - pattern detected" - simple count per fence section
 Dashboard card: open incidents count, trend graph
6e. Status Workflow
 Open -> En Route (someone accepted) -> Resolved -> Closed
 Anyone in farm group can update status + add photo of fixed fence
 FCM notification on status change
6f. Roles & Audience Separation
 hunter (R34.99): Can REPORT alerts (free to report) - sees own farm alerts only - map view of own incidents
 internationalHunter ($5.99): Same as hunter - can report if guest on farm - sees international pricing not relevant here - map view free
 outfitter (R299.99): RECEIVES all alerts for farms they manage + can assign workers + view all incidents + export PDF - this justifies R299 tier
 butchery/taxidermy: Not in Farm Watch - hide tab
 admin: Sees all farms analytics
6g. Technical Notes - Minimal Change
 Reuse existing TrackIdentifierScreen camera for photo capture + compress to 800px
 Use existing location service + geolocator - already have GPS
 New: AlertService - SQLite queue (sqflite) - queueAlert() + syncWhenOnline() (connectivity_plus)
 Voice: record package m4a max 10s
 Push: existing FCM - new topic farm_{farmId}
 Photos: compress 800px, save to Firebase Storage alerts/{id}/
 Offline first: all saves local first, then sync
6h. Monetization
 Included in Outfitter R299.99 - no extra charge - pitch: "One prevented incident = 50 months paid"
 Hunter R34.99 / International $5.99: Free to report, outfitter pays to receive - included in base sub
 Optional add-on: R49/mo SMS alerts via Twilio - addons/smsAlerts { farmId, active, phoneNumbers[] } - for areas with no data
6i. Build Order (12h part-time) - Spec Only
Week 1 (4h): Alert button UI 4 big buttons + GPS grab + offline save SQLite + queue
Week 2 (5h): Map view pins + broadcast farm group FCM + WhatsApp intent + polygon draw
Week 3 (3h): Incident log list + status update + PDF export insurance
6j. Canva Assets Needed
Alert icons: Flame red, fence cut, rifle cross, paw - 512x512 PNG
Empty state: "No incidents - farm safe" green check
6k. Acceptance Criteria
 Tap 🔥 button -> GPS saved offline even with airplane mode -> appears in queue -> auto sends when online
 Map shows farm boundary + red pin at alert location
 Push received by farm owner within 5 sec when online
 PDF export includes photos + GPS + cost
 Works offline in Kalahari (tested airplane mode)
Total: ~12h, reuses camera + GPS + FCM, offline first.

7. NR9: PLAASBESTUUR LITE - Water & Feeding + Carrying Capacity (SPEC ONLY)
Status
Date: Nov 2026 | Build: Jan-Feb 2027, 20h | Unlocks R599 tier | Pitch: "R599 to save R100k"

Problem in SA
Outfitters use paper notebooks: "Fed camp 3, 500kg, 12 Nov" - no history, no cost tracking
Overstocking = veld damage 3 years, DAFF can fine
Borehole diesel costs huge, water tracking critical for drought
No app calculates carrying capacity using official SA DAFF guidelines
Goal
Simple farm manager that calculates carrying capacity + tracks water/feed costs - upgrade tier R599 Pro

7a. Water Dashboard
 Add borehole: farms/{farmId}/boreholes/{id} { name: Boorgat 1, gps, depthM: 80, pumpType: diesel|solar|eskom, capacityLPerHour, active }
 Daily log (30 sec): waterLogs/{id} { date, boreholeId, hoursPumped, liters auto calc hours*capacity, dieselUsedL, dieselCostR, photoMeterUrl }
 Dashboard:
Water level trend graph last 30 days (MPAndroidChart / fl_chart)
Avg hours/day vs today - alert: "Boorgat 1 only 1.2h today vs avg 3h - check pump" (local notification)
Diesel cost this month, total water pumped this month
 Rain gauge log: rainLogs/{id} { date, mm, camp } -> auto veld growth estimate: "45mm this month - good growth expected"
 Screen: WaterDashboardScreen - borehole list + log button + graph
7b. Feeding Log
 Setup Camps: farms/{farmId}/camps/{id} { name: Camp A, sizeHa: 200, veldType: Sweetveld|Sourveld|Mixed|Kalahari|Karoo, condition: Good|Average|Poor, currentLSU: auto }
 Log feeding (45 sec): feedLogs/{id} { date, campId, feedType: pellets|lusern|mielies|lek, kg, costPerKg, total auto, supplier, photoReceiptUrl }
 Auto calculations:
Cost per camp per month, cost per animal per month (total feed cost / total animals in camp)
Total feeding cost vs hunting income for that camp
 Alerts: "Camp C not fed in 7 days", "Feed cost R12k vs income R8k - loss" - local notif
 Screen: FeedingLogScreen
7c. Carrying Capacity Calculator (KILLER FEATURE - SA ONLY - No other app has this)
 Official DAFF guidelines - store as JSON lookup table assets/daff_capacity.json:
Input: Farm size ha, Veld type, Rainfall Low (<400mm) / Med (400-600) / High (>600), Veld condition Good/Avg/Poor
Formula: ha per LSU table:
Sweetveld good 12-14 ha/LSU, avg 16, poor 21
Sourveld good 18-20, avg 22, poor 30
Mixed good 15, avg 18, poor 25
Kalahari good 25-30, avg 35, poor 45
Karoo good 20, avg 28, poor 40
Adjust: Poor = +50% ha/LSU (as spec)
Output: MAX LSU = farmSizeHa / haPerLSU
Example: 1200ha Sweetveld High Good = 85 LSU max
 Current stock: farms/{farmId}/camps/{campId}/game/{speciesId} { species: kudu, count: 30, lsuPerAnimal: 0.8, totalLSU: 24 }
 LSU TABLE (20 species - include in assets):
Eland 1.2, Kudu 0.8, Blue Wildebeest 0.7, Red Hartebeest 0.6, Gemsbok 0.6, Zebra 0.7, Impala 0.15, Blesbok 0.15, Springbok 0.08, Warthog 0.2, Waterbuck 0.7, Sable 0.75, Roan 0.8, Nyala 0.4, Bushbuck 0.25, Duiker 0.05, Steenbok 0.04, Ostrich 0.3, Giraffe 1.5, Buffalo 1.0
 Result dashboard:
"You have 45.5 LSU of 85 max (53% capacity)"
"You can add: 12 impala OR 2 kudu bulls OR 1 eland bull" - auto calc remaining LSU / lsuPerSpecies
"Camp A: 90% full - do not add" (red), "Camp B: 40% full - can move 10 impala from A to B" (green)
Visual: Pie chart per camp green/yellow/red (green <70%, yellow 70-90%, red >90%)
 Screen: CapacityCalculatorScreen - inputs + result + pie chart
7d. Staff Tasks
 Simple task list: farms/{farmId}/tasks/{id} { title: Check fence North, assignedTo: Jan, due: date, priority: High/Med/Low, status: Open/Done, photoProofUrl, gpsDone, doneAt }
 Shows log: Who did what, when, with photo proof - reuse camera + GPS
 Screen: StaffTasksScreen
7e. Cost Dashboard (Farm Profit)
 Monthly view: costDashboard/{farmId}/{month} { income: hunting R45k, accommodation R10k, expenses: diesel R4k, feed R12k, staff R15k, maintenance R3k, profit auto R21k }
 Auto pull: water diesel cost + feeding cost from logs - manual income/expense entry for rest
 Per farm, per camp breakdown
 Export Excel/CSV for accountant - excel package
 Screen: CostDashboardScreen - bar chart income vs expense
7f. Compliance Notes
 Reminders: "Game count due for DAFF - 30 Nov" - local notification scheduled
 Store docs: farms/{farmId}/documents/{id} { type: registration|permit, fileUrl, expiry } - reuse existing License Wallet Nr1
7g. Roles & Monetization - Two Tiers (Critical)
 Current R299 tier: JagSpoor Outfitter = Hunt bookings + Trophy stock + Marketplace hunt packages + NR5 Farm Watch (alerts)
 NEW R599 tier: Plaasbestuur Pro = Everything in R299 + Water + Feeding + Capacity + Staff + Cost dashboard + Excel export
 Pitch: "One prevented overgrazing saves R100k in veld rehab. One borehole failure detected early saves R20k pump."
 Target: 50 farms x R599 = R29,950 MRR - HuntX pitch: "JagSpoor is not hunting app - it's farm protection + farm profit. R599 to save R100k."
 Firestore: subscriptions/{uid} { tier: outfitter_basic R299 | outfitter_pro R599 } - gate screens by tier
 Hunter roles: hunter R34.99 + internationalHunter $5.99 - can VIEW farm data if shared by outfitter (read-only) - not edit
7h. Technical Notes - Minimal Change
 All data offline first, sync when online - reuse SQLite queue from NR5
 Simple tables, no complex GIS - polygon draw already from NR5 map
 Capacity formula: JSON lookup easy to update
 Graphs: fl_chart (already used?) or MPAndroidChart free
 Reuse existing camera for receipt/meter photos
 Reuse existing GPS service
7i. Build Order (20h part-time) - Spec Only
Week 1 (8h): Water dashboard + borehole add + daily log + graph + rain gauge
Week 2 (6h): Feeding log + camps setup + carrying capacity calculator with LSU table + pie chart
Week 3 (6h): Cost dashboard + staff tasks + Excel export + tier gating R299 vs R599
7j. Canva Assets Needed
Icons: Water drop blue, feed bag brown, LSU cow icon, staff icon - 512x512
Dashboard template: "Farm dashboard minimal"
7k. Acceptance Criteria
 Add borehole Boorgat 1, log 3h pumping -> auto liters + graph shows 3h
 Add Camp A 200ha Sweetveld Good -> calculator shows max LSU -> add 30 kudu -> shows 53% capacity + can add 12 impala
 Feed log R12k vs income R8k -> alert loss
 Cost dashboard shows profit R21k + export CSV opens in Excel
 R299 tier cannot open Water dashboard - shows upgrade to R599 modal
 Works offline - logs queue, syncs when online
Total: ~20h, reuses NR5 map + SQLite queue + camera, unlocks R599 tier.

8. CURRENT STACK SUMMARY (Updated Nov 2026)
DONE
✅ Nr1 License Wallet (SAPS expiry alerts, offline PDFs)
✅ Nr6 Biltong/Butchery Tracker (tag -> butcher -> kg)
✅ Nr7 Snake/Spoor ID Offline (30 snakes + spoor, offline) + UV Fluorescence FREE (Phase 4) - both roles free
WIP
🔨 Nr8 Taxidermist Tracker (with local vs international pricing separation)
NEXT (Spec Only - Do Not Build)
⭐ Nr5 Veldbrand & Poaching Alert - Farm Watch Tab (12h, Dec build, included in R299 outfitter, hunters free to report) - Phase 6
⭐ Nr9 Plaasbestuur Lite - Water & Feeding + Carrying Capacity (20h, Jan-Feb build, unlocks R599 Pro tier) - Phase 7
After These Two + Marketplace
Marketplace Phase 5: Safari Outdoor killer - free with sub, verified sellers
You can pitch at HuntX: "JagSpoor is not a hunting app - it's farm protection + farm profit. R299 to stop poaching, R599 to save R100k."
Final Pricing Tiers (Locked)
hunter: R34.99/mo ZAR - trophy log, hunts (local), butchery/taxidermy nearby, marketplace selling, UV free, can report farm alerts
internationalHunter: $5.99/mo USD - same as hunter but international pricing, Gold Standard, OR Tambo, SAPS 520, marketplace USD
outfitter R299.99/mo: Basic - hunt bookings (local+intl separated), farm watch alerts, marketplace hunt packages
outfitter Pro R599/mo: Everything Basic + water + feeding + carrying capacity + staff + cost dashboard + Excel export (NR9)
butchery R149.99/mo: Local + International pricing separated, marketplace services
taxidermy R149.99/mo: Local + International pricing separated + dip/pack + shipping, Gold Standard
Optional SMS add-on: R49/mo via Twilio for farm alerts no-data areas
Build Phases (All Spec Only)
Phase 1: Roles + Pricing separation (2h)
Phase 2: Gold Standard badge (3h)
Phase 3: Butchery/Taxidermy roles (4h)
Phase 4: UV Fluorescence free (8h)
Phase 5: Marketplace Safari killer (16h)
Phase 6: NR5 Farm Watch (12h)
Phase 7: NR9 Plaasbestuur Pro R599 tier (20h)
Total: ~65h part-time - no breaking changes to 1.0.11 in Play review
