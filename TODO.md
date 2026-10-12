@'

\# JagSpoor - TODO (International Hunters + Services)

Last updated: 2026-10-12

Status: SPEC ONLY - DO NOT BUILD YET



\## 1. ALREADY POSTED - International Hunter Side (from yesterday)



\### Goal

International Hunter is just a role (`UserRole`) like hunter/outfitter/butchery/taxidermy - not a separate app or profile type. Same base user, different role flag.



\### Features

\- \[ ] Add `UserRole.internationalHunter` to roles enum (alongside hunter, outfitter, butchery, taxidermy, admin) - \*\*just a role\*\*

\- \[ ] Onboarding fields for this role: passport no, country, firearm import docs (SAPS 520), home outfitter linkage

\- \[ ] Document vault (role-gated): upload SAPS, customs, flight details - encrypted storage

\- \[ ] Outfitter matching: role `internationalHunter` can search SA outfitters, see packages, trophy pricing (same UI as hunter)

\- \[ ] Currency toggle: ZAR / USD / EUR - auto convert pricing (role preference)

\- \[ ] Trip planner: dates, species wishlist, travel checklist

\- \[ ] Compliance: SAPS 520 auto-fill from profile + trip

\- \[ ] Chat with outfitter + translator helper



\### Firestore (role-based, not separate collection)

\- `users/{uid}` { role: "internationalHunter", ...existing hunter fields + passport, country }

\- `users/{uid}/documents/{docId}` (or `internationalDocs` subcollection)

\- `trips/{tripId}` { hunterId, outfitterId, dates, species\[], status } - hunterId can have role internationalHunter

\- All existing hunter logic reused - just check `role == internationalHunter` for extra fields



\---



\## 2. NEW - Butchery \& Taxidermy Profiles (ADDED TODAY - SPEC ONLY)



\### Goal

Build 2 more roles just like International Hunter: BUTCHERY and TAXIDERMY - all 5 roles use same UserRole enum.



\### 2a. Roles (all just roles)

\- `enum UserRole { hunter, internationalHunter, outfitter, butchery, taxidermy, admin }`

\- All roles share `users/{uid}` base doc with `role` field

\- No separate apps - just role flag + role-specific onboarding + dashboard

\- Onboarding: business name, location (lat/lng), service area radius km, contact, license no (role-gated)

\- Dashboard for each



\### 2b. Butchery - Pricing Management

\- Must be able to load/manage service pricing:

&#x20;   - Services: Skinning, Cutting, Vacuum Pack, Sausage, Biltong, Mince, Dry Wors, etc.

&#x20;   - Model: name, category, price, unit (perKg/perAnimal/fixed), species (optional), turnaroundDays, notes, active

&#x20;   - Screen: ButcheryPricingScreen (CRUD)

&#x20;   - Firestore: `butcheries/{uid}/pricing/{serviceId}`

\- Availability + service area



\### 2c. Taxidermy - Pricing Management

\- Must be able to load/manage service pricing:

&#x20;   - Mount types: Shoulder, Full mount, Skull, Rug, Flat skin, Pedestal, etc.

&#x20;   - Model: name, species, price, deposit, turnaroundMonths, portfolioImages\[], active

&#x20;   - Screen: TaxidermyPricingScreen

&#x20;   - Firestore: `taxidermists/{uid}/pricing/{serviceId}`



\### 2d. Hunter Side - Search \& Book (Domestic + International)

\- Search nearby butchery/taxidermy:

&#x20;   - Use geolocator + geo query (geohash)

&#x20;   - Screens: FindButcheryScreen / FindTaxidermyScreen

&#x20;   - Filters: distance slider, rating, price range, availability

&#x20;   - View: Map (flutter\_map) + List sorted by distance

\- See loaded pricing: when hunter taps provider, show full pricing table + calculator (qty \* price)

\- Book it:

&#x20;   - Select service(s) -> qty (kg / nr animals) -> requested date -> notes / trophy tag no

&#x20;   - Create: `bookings/{id}` { hunterId, providerId, providerType: butchery|taxidermy, services\[], estimatedTotal, status: pending/confirmed/completed, hunterLocation }

&#x20;   - FCM notification to provider

&#x20;   - Provider can accept/decline + set final price

&#x20;   - Booking history both sides

&#x20;   - Works for international hunters too (same flow, adds trip linkage)



\### Data Model

```dart

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

