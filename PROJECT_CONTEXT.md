# 🏔️ JagSpoor v4.2 - Core System Architecture Blueprint

> **Version:** 4.2 | **Platform:** Flutter / Firebase | **Currency:** ZAR (South African Rand) | **Last Updated:** 2026-07-30

---

## 1. Role-Based Access Control & Dashboard Isolation

### 1.1 Outfitter Enterprise Cockpit (`outfitter_dashboard.dart`)
Six operational cards accessible **only** to verified master outfitters:

| Card | Function | Access Level |
|------|----------|--------------|
| Manage Farms & Managers | Multi-tenant farm/manager assignment | Master Outfitter |
| Trophy Stock Inventory | Species/population management | Master Outfitter |
| Publish Hunting Package | Create/edit package listings | Master Outfitter |
| Incoming Booking Requests | Client negotiation queue | Master Outfitter |
| Financial Revenue Summary | Revenue analytics & reporting | Master Outfitter |
| Issue Game Transport Permit | PDF permit generation | Master Outfitter |

### 1.2 Farm Manager HUD (Isolation Restrictions)
- **Restricts** assigned manager profiles from:
  - Global corporate financial dashboards
  - Package editors
  - Revenue metrics views
- **Locks** dropdown forms strictly to their assigned `farmId`
- Enforces row-level security via Firestore rules

### 1.3 Hunter Mode Dashboard (`hunter_dashboard.dart`)
Streamlined client view panel stripped of all administrative tools:
- Field navigation tools
- Tactical enhancement widgets
- Marketplace booking interface
- Trophy browser access

---

## 2. Marketplace & Financial Layer (Locked to ZAR)

### 2.1 Automated 5% Platform Burner (`package_booking_manager.dart`)
- Calculates `5%` platform admin fee during package upload
- Writes directly to Firestore package document:
  - `platformCommissionZAR`
  - `totalPriceZAR`
- Non-negotiable fee structure enforced at data layer

### 2.2 Checkbox Itinerary Package Builder (`hunter_custom_package_builder_screen.dart`)
- Allows hunters to mix and match:
  - Individual species selections
  - Services from scanned pricelists
- **Live running sum total** display
- Persists selections to `/bookings` on confirmation

### 2.3 Unified Trophy Registry (`hunter_trophy_browser_screen.dart`)
- Queries flat root `/trophies` collection
- Filters by:
  - Province
  - Stock count
- Instant cross-role synchronization (Outfitter ↔ Hunter)

### 2.4 In-App Booking Negotiation Threads (`chat_and_filter_service.dart`)
- Real-time bidirectional messaging
- Subcollections nested: `/bookings/{bookingId}/chats`
- Color-coded high-contrast HUD styling
- Timestamp tracking per message

---

## 3. Off-Grid Navigation & Local Caching Infrastructure

### 3.1 Offline Sync Queue Manager (`offline_sync_queue.dart`)
Local SQLite fallback transaction engine:
- Buffers data during cell tower failure:
  - Waypoints
  - Carcass logs
  - Targets
- **No telemetry drops** during connectivity loss
- Auto-syncs when connection restored

### 3.2 Topographic Breadcrumb Path Tracer (`map_path_tracer.dart`)
- Continuous location data tracking
- Streams from `Geolocator` package
- Overlays on offline topographic vector map layers
- Blood spoor trail support

### 3.3 Carcass-to-Waypoint Auto-Pinning Shortcut
- Captures current high-accuracy GPS position
- Falls back to last known breadcrumb vector node
- Binds spatial data atomically into:
  - Carcass harvest matrix forms
  - Waypoint collection

### 3.4 Time-Series Radius Filtering Toolbar (`offline_navigation_screen.dart`)
- Sliding diagnostic panel
- Calculates:
  - Offline Haversine distance geometry
  - Timestamp age deltas
- Clears map canvas clutter automatically

---

## 4. Advanced Tactical Hardware & Vision Pipelines

### 4.1 BLE Laser Rangefinder Telemetry Bridge (`advanced_tactical_service.dart`)
- Couples phone magnetic compass heading streams (`flutter_compass`)
- Bluetooth rangefinder GATT notification parsing
- Projects precise target markers along hunter's line of sight
- **Entirely offline operation**
- Auto-syncs projected targets to `OfflineSyncQueue`

### 4.2 Hardware-Driven Activity Forecaster HUD (`network_diagnostic_hud.dart`)
- Binds to internal hardware barometric pressure sensor (`environment_sensors`)
- Overhead solunar transit calculations
- Streams dynamic game movement probability ticker:
  ```
  🦌 AI GAME MOVEMENT ACTIVITY FORECASTER: 82% (PEAK MOVEMENT WINDOW - INCOMING WEATHER FRONT)
  ```
- Metrics: Pressure in hPa, weather condition, moon phase %, SOLUNAR badge

### 4.3 Predator Ironbow Pseudo-Thermal Shader (`blood_tracker_screen.dart`)
False-color matrix color filter shader:
- **Suppresses** green/brown foliage wavelengths
- **Amplifies** luminance deltas aggressively
- Blood drop trails pop in **neon orange/yellow**
- Game silhouettes enhanced with high contrast

**Ironbow Matrix:**
```dart
final List<double> thermalMatrix = <double>[
  -1.0,  2.0,  2.0, 0.0, -50.0,  // R: aggressive luminance amplification
   2.0, -1.0,  0.0, 0.0, -100.0,  // G: crush foliage wavelengths
   0.0,  0.0,  3.0, 0.0, 100.0,   // B: lift cold shadows to blue/indigo
   0.0,  0.0,  0.0, 1.0,   0.0,   // Alpha: transparency stability
];
```

### 4.4 Ballistic Scope Calibration & Reticle HUD System (`scope_calibration_screen.dart`)
Offline point-mass ballistic calculator featuring:
- **Rifle drag profile parsing** (G1/G7 ballistic coefficients)
- **Scope click value inputs** (MOA, MIL, IPHY adjustment resolution)
- **Barometric metrics integration** (temperature, pressure, humidity corrections)
- **Laser distance telemetry** (auto-populated from rangefinder via `advanced_tactical_service.dart`)
- **Interactive turret click dial HUD overlay** displaying:
  - Elevation adjustments in current unit system
  - Windage corrections with direction indicators
  - Dope card (Data On Previous Engagement) history
  - Zero range confirmation marker

### 4.5 Ballistic Trajectory Solver Engine (`ballistic_solver_service.dart`)
Central offline ballistic processing engine providing:
- **Point-mass trajectory calculation** with gravity (32.174 ft/s²)
- **Slant-range cosine angle corrections** for uphill/downhill shots
- **Air density factor** derived from barometric pressure (hPa)
- **MOA/MRAD conversion** with integer click count output
- **Effective range estimation** based on maximum allowable drop
- **Trajectory table generation** for dope card building

### 4.6 Interactive Vital Zone Anatomy HUD Overlay (`vital_zone_painter.dart`)
Vector-drawn anatomical overlay engine for precision shot placement:
- **Species-specific overlays** for Kudu, Impala, Warthog, and other SA game
- **Anatomical structure targeting**: Heart, lung, and skeletal vital zones
- **Camera radar integration** with live overlay rendering
- **Color-coded zone highlighting**: Red for lethal, orange for marginal, yellow for reference
- **Distance-scaled overlays** adjusting zone size based on estimated range
- **Shot angle compensation** for quartering-away/quartering-toward presentations

---

## 5. Compliance & Documentation Exporters

### 5.1 A4 PDF Manifest Generators
| Exporter | Document Type | Output |
|----------|--------------|--------|
| `outfitter_invoice_exporter.dart` | ZAR-locked billing statements | A4 PDF |
| `transport_permit_pdf_exporter.dart` | SA Game Transport Certificates | A4 PDF |

### 5.2 Digital Finger-Drawing Signature Canvas (`signature/`)
- High-fidelity local canvas capturing
- Landowner's handwritten signature
- Burns graphic directly onto transport permit PDF
- Native system sharing sheet launch

---

## 6. Service Architecture Map

```
lib/
├── core/
│   └── theme/
│       └── app_theme.dart           # Unified HUD styling system
├── features/
│   ├── auth/
│   │   └── screens/                 # Login, registration, password reset
│   ├── hunter_mode/
│   │   ├── screens/
│   │   │   ├── hunter_dashboard.dart           # Client home panel
│   │   │   ├── hunter_custom_package_builder_screen.dart  # Package builder
│   │   │   ├── hunter_trophy_browser_screen.dart         # Trophy registry
│   │   │   ├── blood_tracker_screen.dart                 # Thermal camera
│   │   │   ├── offline_navigation_screen.dart            # Topographic map
│   │   │   └── outfitter_booking_dashboard_screen.dart  # Booking queue
│   │   ├── services/
│   │   │   ├── advanced_tactical_service.dart    # BLE rangefinder math
│   │   │   ├── ballistic_solver_service.dart      # Ballistic trajectory engine
│   │   │   ├── offline_sync_queue.dart           # SQLite fallback
│   │   │   ├── map_path_tracer.dart              # Breadcrumb tracking
│   │   │   └── chat_and_filter_service.dart      # Negotiation threads
│   │   └── widgets/
│   │       └── network_diagnostic_hud.dart        # Game activity forecaster
│   └── outfitter_mode/
│       ├── screens/
│       │   ├── outfitter_dashboard.dart          # Enterprise cockpit
│       │   ├── package_booking_manager.dart        # 5% burner logic
│       │   ├── outfitter_invoice_exporter.dart   # PDF billing
│       │   └── transport_permit_pdf_exporter.dart # Transport certificates
│       └── services/
│           └── signature/                        # Signature capture canvas
└── shared/
    └── firebase/                    # Firestore security rules
```

---

## 7. Firestore Collections Reference

| Collection | Purpose | Access Rules |
|------------|---------|--------------|
| `/users` | User profiles & roles | Authenticated read, admin write |
| `/farms` | Farm entities | Owner/FM restricted |
| `/packages` | Hunting packages + 5% fee | Published/managed by outfitter |
| `/bookings` | Client bookings | Owner + assigned outfitter |
| `/bookings/{id}/chats` | Negotiation messages | Owner + assigned |
| `/trophies` | Trophy stock registry | Global read, outfitter write |
| `/waypoints` | Map markers + rangefinder targets | Owner + FM restricted |
| `/scanned_pricelists` | Parsed price list data | Outfitter managed |

---

## 8. Security & Compliance Notes

- **Currency Lock:** All financial operations denominated in ZAR only
- **Role Isolation:** Farm managers cannot access corporate views
- **Offline Integrity:** SQLite queue guarantees no data loss
- **Audit Trail:** All booking state changes timestamped in subcollections
- **Signature Binding:** Handwritten signatures immutably embedded in permits

---

*Generated: 2026-07-30 | JagSpoor v4.2 Architecture Blueprint*
