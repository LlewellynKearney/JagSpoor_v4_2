JagSpoor - TODO (International Hunters + Services)

Last updated: 2026-10-12

Status: SPEC ONLY - DO NOT BUILD YET



1\. ALREADY POSTED - International Hunter Side (from yesterday)

Goal

International Hunter is just a role (UserRole) like hunter/outfitter/butchery/taxidermy - not a separate app or profile type. Same base user, different role flag.



Features

&#x20;Add UserRole.internationalHunter to roles enum (alongside hunter, outfitter, butchery, taxidermy, admin) - just a role

&#x20;Onboarding fields for this role: passport no, country, firearm import docs (SAPS 520), home outfitter linkage

&#x20;Document vault (role-gated): upload SAPS, customs, flight details - encrypted storage

&#x20;Outfitter matching: role internationalHunter can search SA outfitters, see packages, trophy pricing (same UI as hunter)

&#x20;Currency toggle: ZAR / USD / EUR - auto convert pricing (role preference)

&#x20;Trip planner: dates, species wishlist, travel checklist

&#x20;Compliance: SAPS 520 auto-fill from profile + trip

&#x20;Chat with outfitter + translator helper

Firestore (role-based, not separate collection)

users/{uid} { role: "internationalHunter", ...existing hunter fields + passport, country }

users/{uid}/documents/{docId} (or internationalDocs subcollection)

trips/{tripId} { hunterId, outfitterId, dates, species\[], status } - hunterId can have role internationalHunter

All existing hunter logic reused - just check role == internationalHunter for extra fields

2\. NEW - Butchery \& Taxidermy Profiles (ADDED TODAY - SPEC ONLY)

Goal

Build 2 more roles just like International Hunter: BUTCHERY and TAXIDERMY - all 5 roles use same UserRole enum.



2a. Roles (all just roles)

enum UserRole { hunter, internationalHunter, outfitter, butchery, taxidermy, admin }

All roles share users/{uid} base doc with role field

No separate apps - just role flag + role-specific onboarding + dashboard

Onboarding: business name, location (lat/lng), service area radius km, contact, license no (role-gated)

Dashboard for each

2b. Butchery - Pricing Management

Must be able to load/manage service pricing:

Services: Skinning, Cutting, Vacuum Pack, Sausage, Biltong, Mince, Dry Wors, etc.

Model: name, category, price, unit (perKg/perAnimal/fixed), species (optional), turnaroundDays, notes, active

Screen: ButcheryPricingScreen (CRUD)

Firestore: butcheries/{uid}/pricing/{serviceId}

Availability + service area

2c. Taxidermy - Pricing Management

Must be able to load/manage service pricing:

Mount types: Shoulder, Full mount, Skull, Rug, Flat skin, Pedestal, etc.

Model: name, species, price, deposit, turnaroundMonths, portfolioImages\[], active

Screen: TaxidermyPricingScreen

Firestore: taxidermists/{uid}/pricing/{serviceId}

2d. Hunter Side - Search \& Book (Domestic + International)

Search nearby butchery/taxidermy:

Use geolocator + geo query (geohash)

Screens: FindButcheryScreen / FindTaxidermyScreen

Filters: distance slider, rating, price range, availability

View: Map (flutter\_map) + List sorted by distance

See loaded pricing: when hunter taps provider, show full pricing table + calculator (qty \* price)

Book it:

Select service(s) -> qty (kg / nr animals) -> requested date -> notes / trophy tag no

Create: bookings/{id} { hunterId, providerId, providerType: butchery|taxidermy, services\[], estimatedTotal, status: pending/confirmed/completed, hunterLocation }

FCM notification to provider

Provider can accept/decline + set final price

Booking history both sides

Works for international hunters too (same flow, adds trip linkage)

Data Model

enum ProviderType { butchery, taxidermy }

enum PriceUnit { perKg, perAnimal, fixed }

class ServicePricing {

&#x20; String id;

&#x20; String name;

&#x20; String category;

&#x20; double price;

&#x20; PriceUnit unit;

&#x20; String? species;

&#x20; int turnaroundDays;

&#x20; String? notes;

&#x20; bool active;

&#x20; List<String>? portfolioImages; // taxidermy

}

class Booking {

&#x20; String id;

&#x20; String hunterId;

&#x20; String providerId;

&#x20; ProviderType providerType;

&#x20; List<BookingItem> items;

&#x20; double estimatedTotal;

&#x20; DateTime requestedDate;

&#x20; BookingStatus status;

&#x20; GeoPoint? hunterLocation;

&#x20; String? tripId; // link to international trip if applicable

}

Acceptance Criteria (for future build)

&#x20;Butchery CRUD pricing

&#x20;Taxidermy CRUD pricing + portfolio

&#x20;Hunter search nearby (within X km) butcheries \& taxidermists - works offline cache?

&#x20;Hunter sees pricing before booking

&#x20;Booking creates notification + provider dashboard entry

&#x20;International hunter can also search/book (with tripId)

&#x20;Security rules updated for butcheries, taxidermists, bookings

&#x20;Tests for pricing + booking

Payments - Monthly Subscription (All Roles)

&#x20;Subscription model for ALL roles - same modal, different prices:

hunter: existing local hunter subscription (keep current price)

internationalHunter: same modal/flow as hunter, different price tier (higher - USD based)

outfitter: provider plan (existing)

butchery: provider plan

taxidermy: provider plan

&#x20;Plans structure - FINAL PRICES (per month):

hunter: R34.99/mo (ZAR)

internationalHunter: $5.99/mo (USD) - same modal/flow as local hunter, different price

outfitter: R299.99/mo (ZAR)

butchery: R149.99/mo (ZAR)

taxidermy: R149.99/mo (ZAR)

Billing: Google Play Billing (existing BILLING permission) + RevenueCat / Stripe for web - reuse current billing implementation

Same paywall modal/widget for all roles - just pass UserRole to get price/currency

Google Play Console: create 5 subscription products: hunter\_monthly, intl\_hunter\_monthly, outfitter\_monthly, butchery\_monthly, taxidermy\_monthly

&#x20;Firestore: subscriptions/{uid} { role, plan, price: 34.99|5.99|299.99|149.99, currency: ZAR|USD, status: active/trialing/past\_due/canceled, currentPeriodEnd, providerType }

&#x20;Gate:

Hunters (local + international): gate trophy log, hunt search, booking, document vault behind active sub

Providers (outfitter/butchery/taxidermy): gate pricing CRUD \& receiving bookings behind active sub

&#x20;Check subscription on dashboard load -> if inactive, show paywall modal (same modal as hunter)

&#x20;Free trial 14 days for new butchery/taxidermy + internationalHunter

&#x20;Webhook handling for renewals/cancellations (Cloud Functions)

&#x20;Hunter still pays provider directly offline - subscription is app access fee only

Out of scope (later)

In-app chat (reuse existing)

Reviews v2

Hunter-to-provider payment (handled offline)

NOTES FOR OPENHANDS

DO NOT BUILD NOW - spec only

When build is requested, start with butchery profile, then taxidermy, then hunter search, then booking

Keep existing international hunter TODO untouched



