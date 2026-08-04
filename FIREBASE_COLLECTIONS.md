# Firebase Firestore Collection Mapping

This document maps all Firestore collections used by the JagSpoor app to their endpoints and expected schemas.

## Project ID: `jagspoor`

---

## Core Collections

### 1. `users`
**Purpose:** User accounts and profiles
**Used by:** Authentication, profile screens
```
Document Structure:
{
  uid: string,                    // Firebase Auth UID
  email: string,
  displayName: string,
  role: "hunter" | "outfitter" | "admin",
  telegramId: string?,           // Telegram bot integration
  createdAt: timestamp,
  updatedAt: timestamp,
  // Hunter-specific
  firearmsCount: number,
  trophiesCount: number,
  huntsCompleted: number,
  // Outfitter-specific  
  farmIds: string[],
  businessName: string?
}
```

### 2. `firearms`
**Purpose:** User's registered firearms
**Used by:** Firearm safe screen, ballistics calculator
```
Document Structure:
{
  id: string,
  ownerId: string,               // References users.uid
  make: string,
  model: string,
  caliber: string,
  barrelLength: number?,         // inches
  licenseNumber: string?,
  licenseExpiry: timestamp?,
  serialNumber: string?,
  notes: string?,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 3. `firearms/{firearmId}/ammunition`
**Purpose:** Ammunition stored in each firearm's safe
**Used by:** Ammunition inventory screen
```
Document Structure:
{
  id: string,
  brand: string,
  name: string,
  caliber: string,
  bulletWeight: number,          // grains
  muzzleVelocity: number,        // fps
  ballisticCoefficient: number,
  quantity: number,
  batchNumber: string?,
  purchaseDate: timestamp?,
  notes: string?,
  createdAt: timestamp
}
```

### 4. `ammunition`
**Purpose:** User's ammunition inventory (separate from firearm-specific)
**Used by:** Ammunition screen, ballistics
```
Document Structure:
{
  id: string,
  ownerId: string,
  brand: string,
  name: string,
  caliber: string,
  bulletWeight: number,
  muzzleVelocity: number,
  ballisticCoefficient: number,
  remainingStockCount: number,
  purchaseDate: timestamp?,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 5. `animals`
**Purpose:** Wildlife species database
**Used by:** Animal tracking, trophy classification
```
Document Structure:
{
  id: string,
  speciesName: string,
  commonName: string,
  scientificName: string,
  category: "plains" | "big" | "dangerous",
  description: string,
  averageWeight: number?,        // kg
  imageUrl: string?,
  regions: string[],             // ["Limpopo", "Mpumalanga"]
  huntingSeason: string?,
  minimumCaliber: string?
}
```

### 6. `trophies`
**Purpose:** Hunter's trophy records
**Used by:** Trophy screens, outfitter dashboards
```
Document Structure:
{
  id: string,
  hunterId: string,              // References users.uid
  outfitterId: string?,          // References users.uid
  species: string,
  score: number?,                 // SCI score
  weight: number?,                // kg
  location: string,
  huntDate: timestamp,
  weaponUsed: string?,
  caliber: string?,
  photoUrls: string[],
  certificates: string[],
  latitude: number?,
  longitude: number?,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

---

## Ballistics Catalog Collections

### 7. `factory_ammunition`
**Purpose:** Factory ammunition database
**Used by:** Ballistics calculator, ammunition selection
```
Document Structure:
{
  id: string,
  brand: string,
  name: string,
  caliber: string,
  bulletWeight: number,           // grains
  muzzleVelocity: number,        // fps
  ballisticCoefficient: number,
  bulletType: string?,           // "FMJ", "SP", "HP"
  application: string?,          // "target", "hunting", "defense"
  price: number?
}
```

### 8. `bullets`
**Purpose:** Bullet components database
**Used by:** Ballistics calculator
```
Document Structure:
{
  id: string,
  brand: string,
  name: string,
  caliber: string,
  weight: number,                 // grains
  ballisticCoefficient: number,
  bulletType: string,            // "FMJ", "SP", "HP", "BTSSP"
  sectionalDensity: number?,
  createdAt: timestamp
}
```

### 9. `propellants`
**Purpose:** Powder database
**Used by:** Ballistics calculator
```
Document Structure:
{
  id: string,
  brand: string,
  name: string,
  type: string,                  // "smokeless", "black powder"
  burnRate: string?,             // "fast", "medium", "slow"
  muzzleVelocity: number?,        // typical fps
  notes: string?,
  createdAt: timestamp
}
```

---

## Outfitter Management Collections

### 10. `farms`
**Purpose:** Outfitter's hunting farms/game reserves
**Used by:** Farm management, waypoints
```
Document Structure:
{
  id: string,
  ownerId: string,
  name: string,
  location: string,
  size: number?,                 // hectares
  registeredNumber: string?,
  gpsCoordinates: {
    latitude: number,
    longitude: number
  },
  boundary: GeoPoint[],
  enabledSpecies: string[],
  createdAt: timestamp
}
```

### 11. `outfitter/bookings`
**Purpose:** Client hunting bookings
**Used by:** Booking dashboard, calendar
**Note:** Uses sub-collection path `outfitter/bookings`
```
Document Structure:
{
  id: string,
  clientName: string,
  clientContact: string,
  hunterId: string,              // References users.uid
  outfitterId: string,
  arrivalDate: timestamp,
  departureDate: timestamp,
  status: "pending" | "confirmed" | "in_progress" | "completed" | "cancelled",
  lodgingId: string?,
  vehicleId: string?,
  packageType: string?,
  totalPrice: number?,
  currency: string,               // "ZAR"
  specialRequests: string?,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 12. `outfitter/lodging`
**Purpose:** Lodging units/accommodation
**Used by:** Booking management
**Note:** Uses sub-collection path `outfitter/lodging`
```
Document Structure:
{
  id: string,
  unitName: string,               // "Chalet 1", "Tent 3"
  unitType: string,               // "chalet", "tent", "lodge", "camp"
  capacity: number,               // max guests
  currentOccupants: number,
  status: "vacant" | "occupied" | "maintenance",
  amenities: string[],
  pricePerNight: number?,
  createdAt: timestamp
}
```

### 13. `outfitter/fleet`
**Purpose:** Vehicle fleet management
**Used by:** Fleet management screen
**Note:** Uses sub-collection path `outfitter/fleet`
```
Document Structure:
{
  id: string,
  vehicleName: string,
  vehicleType: string,            // "safari_bakkie", "land cruiser", "trailer"
  licensePlate: string,
  operationalStatus: "active" | "maintenance" | "retired",
  fuelLevelPercentage: number?,    // 0-100
  lastServiceDate: timestamp?,
  mileage: number?,
  createdAt: timestamp
}
```

---

## License & Permit Collections

### 14. `license_applications`
**Purpose:** SAPS license applications
**Used by:** License scanner, renewal screens
```
Document Structure:
{
  id: string,
  hunterId: string,
  licenseType: string,            // "firearm", "hunting", "transport"
  licenseNumber: string,
  firearmId: string?,             // References firearms.id
  applicationDate: timestamp,
  expiryDate: timestamp?,
  status: "pending" | "approved" | "rejected",
  lastChecked: timestamp,
  notes: string?,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 15. `transport_permits`
**Purpose:** Game transport permits
**Used by:** Transport permit manager
```
Document Structure:
{
  id: string,
  hunterId: string,
  permitNumber: string,
  origin: string,
  destination: string,
  species: string[],
  vehicleDetails: string,
  gameWardenName: string?,
  issueDate: timestamp,
  expiryDate: timestamp?,
  status: "valid" | "expired" | "cancelled",
  createdAt: timestamp
}
```

---

## Tracking & Waypoints Collections

### 16. `waypoints`
**Purpose:** GPS waypoints and markers
**Used by:** Navigation screens
```
Document Structure:
{
  id: string,
  userId: string,
  name: string,
  type: "camp" | "water" | "blind" | "landmark" | "blood_trail",
  latitude: number,
  longitude: number,
  altitude: number?,
  notes: string?,
  createdAt: timestamp
}
```

### 17. `spoor_scans`
**Purpose:** Track/spoor analysis records
**Used by:** Track identification
```
Document Structure:
{
  id: string,
  userId: string,
  imageUrl: string,
  classification: string?,       // species identification
  confidence: number?,            // 0-100
  location: GeoPoint?,
  notes: string?,
  createdAt: timestamp
}
```

### 18. `carcass_logs`
**Purpose:** Game carcass tracking
**Used by:** Outfitter carcass management
```
Document Structure:
{
  id: string,
  bookingId: string?,
  outfitterId: string,
  species: string,
  weight: number,
  status: "field" | "cold_room" | "butchered" | "delivered",
  latitude: number,
  longitude: number,
  timestamp: timestamp,
  notes: string?
}
```

---

## Communication Collections

### 19. `chats`
**Purpose:** In-app messaging
**Used by:** Chat screens
```
Document Structure:
{
  id: string,
  participants: string[],          // user IDs
  lastMessage: string,
  lastMessageTime: timestamp,
  unreadCount: Map<string, number>, // userId -> count
  createdAt: timestamp
}
```

---

## Additional Collections

### 20. `packages`
**Purpose:** Hunting packages offered by outfitters
```
Document Structure:
{
  id: string,
  outfitterId: string,
  name: string,
  description: string,
  duration: number,               // days
  species: string[],
  included: string[],             // amenities included
  price: number,
  currency: string,
  isActive: boolean,
  createdAt: timestamp
}
```

### 21. `records`
**Purpose:** General record keeping
```
Document Structure:
{
  id: string,
  type: string,                  // record type
  ownerId: string,
  data: Map<string, any>,
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 22. `assets`
**Purpose:** General asset tracking
```
Document Structure:
{
  id: string,
  name: string,
  type: string,
  ownerId: string,
  details: Map<string, any>,
  status: string,
  createdAt: timestamp
}
```

### 23. `scanned_pricelists`
**Purpose:** Scanned pricing documents
```
Document Structure:
{
  id: string,
  userId: string,
  imageUrl: string,
  parsedData: Map<string, any>,
  source: string?,
  createdAt: timestamp
}
```

### 24. `managers`
**Purpose:** Admin/manager accounts
```
Document Structure:
{
  id: string,
  userId: string,
  permissions: string[],
  region: string?,
  createdAt: timestamp
}
```

### 25. `farm_managers`
**Purpose:** Farm-specific manager assignments
```
Document Structure:
{
  id: string,
  farmId: string,
  userId: string,
  role: string,
  createdAt: timestamp
}
```

### 26. `units`
**Purpose:** Generic unit references (for outfitter/lodging sub-structure)
```
Document Structure:
{
  id: string,
  name: string,
  type: string,
  parentId: string?,
  details: Map<string, any>,
  createdAt: timestamp
}
```

---

## Required Firestore Indexes

Deploy this to Firebase Console via `firebase deploy --only firestore:indexes` or create manually:

```json
{
  "indexes": [
    {
      "collectionGroup": "license_applications",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "hunterId", "order": "ASCENDING" },
        { "fieldPath": "lastChecked", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "lodging",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "unitName", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "fleet",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "operationalStatus", "order": "ASCENDING" },
        { "fieldPath": "vehicleName", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "ammunition",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "firearms",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "trophies",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "hunterId", "order": "ASCENDING" },
        { "fieldPath": "huntDate", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "bookings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "outfitterId", "order": "ASCENDING" },
        { "fieldPath": "arrivalDate", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "bookings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "hunterId", "order": "ASCENDING" },
        { "fieldPath": "arrivalDate", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

---

## Firestore Security Rules

Make sure your Firestore rules allow authenticated users to access their own data:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return request.auth.uid == userId;
    }
    
    // Users can read/update their own profile
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow write: if isOwner(userId);
    }
    
    // Users can only access their own firearms
    match /firearms/{firearmId} {
      allow read, write: if isAuthenticated() && 
        resource.data.ownerId == request.auth.uid;
    }
    
    // Users can only access their own ammunition
    match /ammunition/{docId} {
      allow read, write: if isAuthenticated() && 
        resource.data.ownerId == request.auth.uid;
    }
    
    // Allow read access to catalog collections
    match /factory_ammunition/{docId} {
      allow read: if isAuthenticated();
    }
    
    match /bullets/{docId} {
      allow read: if isAuthenticated();
    }
    
    match /propellants/{docId} {
      allow read: if isAuthenticated();
    }
    
    match /animals/{docId} {
      allow read: if isAuthenticated();
    }
    
    // Outfitter collections - check ownership
    match /outfitter/bookings/{bookingId} {
      allow read, write: if isAuthenticated();
    }
    
    match /outfitter/lodging/{unitId} {
      allow read, write: if isAuthenticated();
    }
    
    match /outfitter/fleet/{vehicleId} {
      allow read, write: if isAuthenticated();
    }
    
    // Default deny
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## Quick Setup Commands

### 1. Initialize Firebase CLI
```bash
npm install -g firebase-tools
firebase login
firebase init firestore
```

### 2. Deploy indexes
```bash
firebase deploy --only firestore:indexes
```

### 3. Deploy rules
```bash
firebase deploy --only firestore:rules
```

### 4. Open Firebase Console
```bash
firebase open firestore
```

---

## Troubleshooting

If collections are empty:
1. Verify Firebase project ID matches `jagspoor`
2. Check Firestore is in the correct region
3. Ensure App Check is configured (or in debug mode)
4. Verify authentication is working
5. Run the Firebase Diagnostic utility in the app
