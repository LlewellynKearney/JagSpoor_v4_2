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

NOTES FOR OPENHANDS
DO NOT BUILD NOW - spec only
When build is requested, follow Phase 1 -> Phase 2 -> Phase 3 order above
All new fields nullable with defaults (audience=both) to keep existing outfitters working
Keep existing international hunter TODO untouched
Gold Standard is sorting/badge, not filter - don't hide existing outfitters from local hunters
