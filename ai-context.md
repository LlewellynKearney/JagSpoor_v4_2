# Jagspoor System Architecture & Agent Constraints


## 1. Core Platform Architecture
- **Marketplace Engine**: Jagspoor is a multi-sided ecosystem connecting South African outfitters/game farms with hunters.
- **Visual Design Identity**: HUD Viewport Profile, Tactical Grid Layouts, Walnut Luxury and Thermal Glow aesthetic palettes (#0xFF8B4513, #0xFFC5A059). All layouts must render securely inside responsive 'SafeArea' viewports.


## 2. Hardcoded Revenue & Financial Rules
- **The 5% Commission Multiplier**: Every package rate, manual outfitter entry, daily lodge fee, bakkie transport cost, and slaughter parameter pulled from the database MUST be multiplied by 1.05 and rounded to two decimal places ('(value * 1.05).toStringAsFixed(2)') before rendering on ANY Hunter-facing viewport profile or A4 statement.
- **Currency Standard**: All pricing fields across all features must use the South African Rand symbol ('R ') exclusively. Dollar ($) notations are strictly forbidden.


## 3. Database Layer Constraints (SQLite Cache Engine)
- **Active Table Schemas (Current Database Version: 3)**:
  * `carcass_records`: id, hunterId, species (SA Game Guide Dropdown), carcassWeight (REAL), slaughterFee (REAL), coldroomDays (INTEGER), status, isDirty (INTEGER DEFAULT 1).
  * `outfitter_packages`: id, packageName, packageLocation, startDate, endDate, packageDescription, basePrice (REAL), includedAnimalsJson (TEXT representation of packed species names and unit quantities), createdAt, updatedAt.
  * `bookings`: id, clientName, contactNumber, lodgingId, vehicleId, arrivalDate, departureDate, status, isDirty (INTEGER DEFAULT 1), createdAt.
- **Offline First Principle**: Writing parameters must prioritize the local SQLite cache with 'isDirty = 1', suppressing intermittent socket drops silently to let outfitter trackers operate in zero-signal zones. Background synchronization handlers ('OutfitterSyncService') must upload dirty strings and trigger '.markClean()' when connection bars return.


## 4. UI/UX Global Design Handshakes
- **Bottom Clearance Safety Padding**: To prevent button widgets from clipping behind native phone navigation pills or gesture bar systems, all bottom sheets, overlay layouts, and footer rows must include dynamic inset calculations:
  'EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 16, left: 20, right: 20, top: 20)'
- **Asset Custom Identity**: The default system application icon launcher must bind to the official brand asset graphic asset located at: 'assets/app logo/logo.png' driven by 'flutter_launcher_icons'.
