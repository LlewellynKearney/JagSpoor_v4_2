import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../hunter_mode/models/booking_status.dart';
import 'demo_reviewer_config.dart';
import 'user_role_provider.dart';

/// Outcome of a demo-reviewer sign-in attempt.
///
/// * [success]  — the review account authenticated (or was already signed in)
///   and the demo dataset was seeded (best-effort).
/// * [failure]  — sign-in itself failed; [errorMessage] carries a review-
///   actionable reason.
class DemoSignInResult {
  final bool success;
  final String? errorMessage;

  const DemoSignInResult._(this.success, this.errorMessage);

  const DemoSignInResult.success() : this._(true, null);
  const DemoSignInResult.failure(String message)
      : this._(false, message);

  bool get isSuccess => success;
}

/// Signs into / provisions the Google Play review ("Demo Reviewer") account
/// and seeds it with representative mock data so a reviewer can instantly
/// showcase the restricted hunting, tracking AND outfitter features:
///
///   * **Hunter profile + dual-role access** (`users/{uid}`: first/last name,
///     phone, email, `role: 'dual'` + `isDualRole: true` +
///     `roles: ['hunter','outfitter']`, `outfitterId` self-link, and an
///     ACTIVE subscription entitlement) so the mandatory-profile +
///     subscription gates admit the reviewer AND the role resolves to
///     [AppRole.dual] (both dashboards + the mode switcher);
///   * **SAPS license applications** (`license_applications`) — several at
///     different stages (Submitted / Provincial / CFR / Printed);
///   * a small **firearm inventory** (`firearms` with nested `ammunition`
///     load profiles + linked optics) backing the Digital Firearm Safe,
///     ballistic calculator + shot-group analyzer;
///   * **Digital Trophy Room entries** (`trophies`) with realistic harvest
///     measurements + an offline **harvest/carcass log**;
///   * the **outfitter showcase**: a registered farm with its service-rate
///     card, a trophy-stock inventory, a published hunting package, an
///     itemized farm price list, and a few client bookings at different
///     workflow stages — so the Outfitter dashboard + booking requests +
///     price-list + trophy-stock screens all render populated.
///
/// All writes are best-effort and idempotent (deterministic-ish doc ids,
/// merge semantics): a Firestore failure (offline / rules not yet deployed /
/// sandbox with no network) is logged and never blocks the reviewer from
/// entering the demo — the UI degrades to the empty states the screens
/// already handle gracefully (blank SAPS list, empty firearm safe, …).
class DemoReviewerService {
  DemoReviewerService._() : _enabledOverride = DemoReviewerConfig.enabled;

  /// Process-wide singleton.
  static final DemoReviewerService instance = DemoReviewerService._();

  // Lazy Firebase accessors so constructing the service before
  // `Firebase.initializeApp()` (cold-launch race / widget test) never throws
  // `[core/no-app]`.
  FirebaseAuth? _authOverride;
  FirebaseFirestore? _firestoreOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// Invoked to perform the demo sign-in. Defaults to the real
  /// `signInWithEmailAndPassword`; tests inject a fake that returns a
  /// non-null [UserCredential].
  Future<UserCredential> Function()? _signInOverride;

  /// Whether the demo entry is active. Mirrors [DemoReviewerConfig.enabled]
  /// but is overridable for tests.
  bool _enabledOverride;

  /// Injects fake auth / Firestore / user identity so the flow is
  /// unit-testable without a live Firebase app.
  @visibleForTesting
  void injectForTesting({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    Future<UserCredential> Function()? signIn,
    bool? enabled,
  }) {
    if (auth != null) _authOverride = auth;
    if (firestore != null) _firestoreOverride = firestore;
    if (signIn != null) _signInOverride = signIn;
    _enabledOverride = enabled ?? DemoReviewerConfig.enabled;
  }

  /// Whether the demo reviewer entry is available.
  bool get isEnabled => _enabledOverride;

  /// The review account's email + password.
  String get demoEmail => DemoReviewerConfig.email;
  String get demoPassword => DemoReviewerConfig.password;

  /// Signs into the demo reviewer account (creating + provisioning it
  /// server-side is handled by the documented provisioning step — a one-time
  /// Firebase Console account create, or the bundled `adminCreateOutfitter`-
  /// style tooling), then seeds the demo dataset.
  ///
  /// [seedDemoData] stamps `role: 'dual'` + `isDualRole: true` +
  /// `roles: ['hunter','outfitter']`, so a fresh sandbox / admin-seeded
  /// `users/{uid}` doc resolves to [AppRole.dual] — the reviewer is admitted
  /// to BOTH the Hunter and Outfitter dashboards and the mode switcher.
  Future<DemoSignInResult> signInDemoReviewer() async {
    if (!isEnabled) {
      return const DemoSignInResult.failure(
        'Demo reviewer access is currently disabled.',
      );
    }
    try {
      // If a session is already active (e.g. a stale route stack re-entered
      // the auth screen), reuse it instead of forcing a duplicate sign-in.
      final current = _auth.currentUser;
      User? user = current;
      if (user == null) {
        final signIn = _signInOverride ??
            (() => _auth.signInWithEmailAndPassword(
                  email: demoEmail,
                  password: demoPassword,
                ));
        final credential = await signIn();
        user = credential.user;
      }
      if (user == null) {
        return const DemoSignInResult.failure(
          'Demo sign-in returned no authenticated user.',
        );
      }

      // Cache the resolved role (dual — both dashboards, stamped below) so
      // the route guard admits the reviewer without a re-fetch.
      UserRoleProvider.instance.setRole(AppRole.dual);

      // Seed the demo dataset (best-effort; a failure never blocks entry).
      await seedDemoData(user.uid);
      return const DemoSignInResult.success();
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'DemoReviewerService: sign-in failed ${e.code}: ${e.message}',
      );
      return DemoSignInResult.failure(
        'Demo sign-in failed: ${e.message ?? e.code}. Please check your '
        'network connection or contact support about the review account.',
      );
    } catch (e) {
      debugPrint('DemoReviewerService: sign-in failed - $e');
      return DemoSignInResult.failure('Demo sign-in failed: $e');
    }
  }

  /// Seeds a representative demo dataset for [uid]. All writes are
  /// best-effort + failure-tolerant; idempotency is achieved through
  /// deterministic suffix ids where practical and set() semantics otherwise.
  Future<void> seedDemoData(String uid) async {
    final db = _firestore;
    final now = DateTime.now();
    final userId = uid;

    // 1. Complete hunter profile + DUAL-ROLE access + active subscription +
    //    self-link. The `role: 'dual'` + `isDualRole: true` +
    //    `roles: ['hunter','outfitter']` triple is what makes the reviewer
    //    usable on BOTH dashboards (see `UserRoleProvider.resolveRole`); the
    //    `outfitterId` self-link satisfies the owner-scoped outfitter rules.
    final profile = <String, dynamic>{
      'firstName': 'Demo',
      'lastName': 'Reviewer',
      'fullName': DemoReviewerConfig.displayName,
      'phone': '+27 82 000 0000',
      'email': DemoReviewerConfig.email,
      'role': DemoReviewerConfig.role,
      'isDualRole': true,
      'roles': DemoReviewerConfig.roles,
      'outfitterId': userId,
      'subscriptionStatus': 'active',
      'subscriptionTier': DemoReviewerConfig.subscriptionTier,
      'subscriptionProvider': 'google_play_billing',
      'subscriptionRenewalDate': Timestamp.fromDate(
        now.add(const Duration(days: 30)),
      ),
      'profileUpdatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await db.collection('users').doc(userId).set(profile, SetOptions(merge: true));
    } catch (e) {
      debugPrint('DemoReviewerService: profile seed failed (non-fatal): $e');
    }

    // 2. SAPS license applications at every stage of the workflow (so the
    //    tracker showcases the progress bars, working-day tallies, firearm
    //    make/calibre/serial pills + expanded FIREARM DETAILS).
    final sapsSamples = <Map<String, dynamic>>[
      {
        'applicationType': 'Section 16 Dedicated Hunting',
        'referenceNumber': 'SAPS-DEMO-10470664',
        'idNumber': '8501015009087',
        'currentStatus': 'Submitted',
        'firearmMake': 'TIKKA T3X',
        'make': 'TIKKA T3X',
        'calibre': '6MM MUSGRAVE',
        'serialNumber': 'OB14468',
        'statusMessage': 'Application captured at the District Firearms Office.',
        'submittedAt': now.subtract(const Duration(days: 21)).toIso8601String(),
      },
      {
        'applicationType': 'Competency Certificate',
        'referenceNumber': 'SAPS-DEMO-10470665',
        'idNumber': '8501015009087',
        'currentStatus': 'Provincial',
        'firearmMake': '',
        'make': '',
        'calibre': '',
        'serialNumber': '',
        'statusMessage': 'Under review at the Provincial Firearms Office.',
        'submittedAt': now.subtract(const Duration(days: 45)).toIso8601String(),
        'provincialDfoReceivedAt': now
            .subtract(const Duration(days: 20))
            .toIso8601String(),
      },
      {
        'applicationType': 'Section 15 Occasional Sport',
        'referenceNumber': 'SAPS-DEMO-10470666',
        'idNumber': '8501015009087',
        'currentStatus': 'CFR',
        'firearmMake': 'CZ 457',
        'make': 'CZ 457',
        'calibre': '.22 LR',
        'serialNumber': 'XY75392',
        'statusMessage': 'Processing at the Central Firearms Registry (CFR).',
        'submittedAt': now.subtract(const Duration(days: 90)).toIso8601String(),
        'provincialDfoReceivedAt': now
            .subtract(const Duration(days: 75))
            .toIso8601String(),
      },
      {
        'applicationType': 'Section 13 – Licence to possess a firearm for self-defence',
        'referenceNumber': 'SAPS-DEMO-10470667',
        'idNumber': '8501015009087',
        'currentStatus': 'Printed',
        'firearmMake': 'GLOCK 19',
        'make': 'GLOCK 19',
        'calibre': '9MM PAR',
        'serialNumber': 'GN90123',
        'statusMessage': 'Licence printed — ready for collection at your police station.',
        'submittedAt': now.subtract(const Duration(days: 180)).toIso8601String(),
        'provincialDfoReceivedAt': now
            .subtract(const Duration(days: 160))
            .toIso8601String(),
      },
    ];
    for (final sample in sapsSamples) {
      final doc = {
        'hunterId': userId,
        'currentStatus': sample['currentStatus'],
        'applicationType': sample['applicationType'],
        'referenceNumber': sample['referenceNumber'],
        'idNumber': sample['idNumber'],
        'firearmMake': sample['firearmMake'],
        'make': sample['make'],
        'calibre': sample['calibre'],
        'serialNumber': sample['serialNumber'],
        'statusMessage': sample['statusMessage'],
        'submittedAt': sample['submittedAt'],
        'createdAt': sample['submittedAt'],
        if (sample['provincialDfoReceivedAt'] != null)
          'provincialDfoReceivedAt': sample['provincialDfoReceivedAt'],
        'lastChecked': now.toIso8601String(),
      };
      try {
        await db.collection('license_applications').add(doc);
      } catch (e) {
        debugPrint('DemoReviewerService: SAPS seed failed (non-fatal): $e');
      }
    }

    // 3. Firearm inventory (Digital Firearm Safe host docs + nested ammo).
    final firearms = <Map<String, dynamic>>[
      {
        'name': 'Tikka T3x',
        'make': 'Tikka',
        'model': 'T3x',
        'caliber': '.308 Win',
        'calibre': '.308 Win',
        'serialNumber': 'T3X-DEMO-001',
        'barrelLength': '22"',
        'scopeClickValue': 0.25,
      },
      {
        'name': 'CZ 457',
        'make': 'CZ',
        'model': '457 Varmint',
        'caliber': '.22 LR',
        'calibre': '.22 LR',
        'serialNumber': 'CZ-DEMO-002',
        'barrelLength': '20"',
        'scopeClickValue': 0.1,
      },
      {
        'name': 'Glock 19 Gen5',
        'make': 'Glock',
        'model': '19 Gen5',
        'caliber': '9mm Parabellum',
        'calibre': '9mm Parabellum',
        'serialNumber': 'GLK-DEMO-003',
        'barrelLength': '4"',
        'scopeClickValue': 0.0,
      },
    ];
    final firearmIds = <String>[];
    for (var i = 0; i < firearms.length; i++) {
      final f = firearms[i];
      final docRef = db.collection('firearms').doc();
      try {
        await docRef.set({
          ...f,
          'ownerId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        firearmIds.add(docRef.id);
        // Nested load profiles for the rifle so the ballistic calculator +
        // ammo manager have data.
        if (i == 0) {
          await docRef.collection('ammunition').doc().set({
            'ownerId': userId,
            'rifleId': docRef.id,
            'bulletWeightGrains': 168,
            'velocityMs': 782.0,
            'ballisticCoefficient': 0.464,
            'remainingStockCount': 120,
            'createdAt': FieldValue.serverTimestamp(),
          });
          await docRef.collection('ammunition').doc().set({
            'ownerId': userId,
            'rifleId': docRef.id,
            'bulletWeightGrains': 150,
            'velocityMs': 853.0,
            'ballisticCoefficient': 0.415,
            'remainingStockCount': 60,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else if (i == 1) {
          await docRef.collection('ammunition').doc().set({
            'ownerId': userId,
            'rifleId': docRef.id,
            'bulletWeightGrains': 40,
            'velocityMs': 439.0,
            'ballisticCoefficient': 0.145,
            'remainingStockCount': 200,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('DemoReviewerService: firearm seed failed (non-fatal): $e');
      }
    }

    // 4. Digital Trophy Room entries.
    final trophies = <Map<String, dynamic>>[
      {
        'species': 'Greater Kudu',
        'harvestDate': now.subtract(const Duration(days: 32)).toIso8601String(),
        'location': 'Waterberg, Limpopo',
        'firearmUsed': 'Tikka T3x (.308 Win)',
        'antlerSpread': 88.0,
        'antlerLength': 152.0,
        'antlerCircumference': 32.0,
        'weight': 240.0,
        'tags': ['Trophy Hunt', 'Dedicated'],
      },
      {
        'species': 'Blesbok',
        'harvestDate': now.subtract(const Duration(days: 18)).toIso8601String(),
        'location': 'Free State',
        'firearmUsed': 'CZ 457 (.22 LR)',
        'antlerSpread': 0.0,
        'weight': 65.0,
        'tags': ['Plains Game'],
      },
      {
        'species': 'Impala',
        'harvestDate': now.subtract(const Duration(days: 5)).toIso8601String(),
        'location': 'Northern Cape',
        'firearmUsed': 'Tikka T3x (.308 Win)',
        'antlerLength': 72.0,
        'weight': 58.0,
        'tags': ['Plains Game', 'Cull'],
      },
    ];
    for (final trophy in trophies) {
      try {
        await db.collection('trophies').add({
          ...trophy,
          'ownerId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('DemoReviewerService: trophy seed failed (non-fatal): $e');
      }
    }

    // 5. Offline/harvest logs (carcass log) so the Slaughterhouse manifest
    //    showcases a live chiller entry.
    try {
      await db.collection('carcass_logs').add({
        'hunterId': userId,
        'tagNumber': 'DEMO-001',
        'species': 'Blesbok',
        'fieldWeightKg': 66.5,
        'hangingWeightKg': 41.2,
        'coldStoragePosition': 'Chiller A – Hook 3',
        'status': 'Hanging',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('DemoReviewerService: carcass seed failed (non-fatal): $e');
    }

    // 6. OUTFITTER SHOWCASE — the dual-role account also owns a small
    //    outfitter enterprise: a registered farm with its service-rate card,
    //    a trophy-stock inventory, a published hunting package, an itemized
    //    farm price list, a per-farm service-rates doc, and a few client
    //    bookings at different workflow stages. Every write targets the
    //    owner-scoped collections (`outfitterId` == uid) the existing
    //    firestore.rules already permit for a signed-in outfitter, and
    //    mirrors the shapes the real ops screens write / read.
    // 6a. Canonical outfitter enterprise profile (`outfitters/{uid}`, created
    //     by the adminCreateOutfitter Cloud Function in production — here we
    //     best-effort a self-describing profile; the Enterprise dashboard
    //     resolves it by uid).
    try {
      await db.collection('outfitters').doc(userId).set({
        'name': 'JagSpoor Demo Outfitters',
        'businessName': 'JagSpoor Demo Outfitters (Review)',
        'uid': userId,
        'outfitterId': userId,
        'ownerId': userId,
        'email': DemoReviewerConfig.email,
        'phone': '+27 82 111 0000',
        'province': 'Limpopo',
        'district': 'Waterberg',
        'role': 'outfitter',
        'verified': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('DemoReviewerService: outfitters profile seed failed (non-fatal): $e');
    }

    // 6b. Registered farm (`farms`), the parent of the showcase.
    final farmDoc = db.collection('farms').doc();
    try {
      await farmDoc.set({
        'name': 'Bosveld Demo Ranch',
        'outfitterId': userId,
        'district': 'Waterberg',
        'province': 'Limpopo',
        'town': 'Lephalale',
        'sizeHectares': 5200,
        'contactNumber': '+27 82 111 0000',
        'registrationNumber': 'DEMO-FARM-2026',
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('DemoReviewerService: farm seed failed (non-fatal): $e');
    }

    // 6c. Farm itemized service-rate card (`farm_service_rates/{farmId}`) so
    //     the Price List + Custom Package Builder render the full rate grid.
    try {
      final rates = <String, dynamic>{
        'farmId': farmDoc.id,
        'outfitterId': userId,
        'rates': {
          'bakkie_vehicle': {
            'key': 'bakkie_vehicle',
            'label': 'Bakkie / Hunting Vehicle Fees',
            'unitLabel': 'Per vehicle per day',
            'quantityNoun': 'vehicles',
            'quantity': 1,
            'pricePerUnit': 1450.0,
            'total': 1450.0,
          },
          'hunter_daily': {
            'key': 'hunter_daily',
            'label': 'Hunter Daily Fees',
            'unitLabel': 'Per day',
            'quantityNoun': 'hunters',
            'quantity': 1,
            'pricePerUnit': 850.0,
            'total': 850.0,
          },
          'overnight_accommodation_hunter': {
            'key': 'overnight_accommodation_hunter',
            'label': 'Overnight Accommodation (Hunter)',
            'unitLabel': 'Per night',
            'quantityNoun': 'nights',
            'quantity': 1,
            'pricePerUnit': 950.0,
            'total': 950.0,
          },
          'coldroom': {
            'key': 'coldroom',
            'label': 'Coldroom / Cold Storage Fees',
            'unitLabel': 'Per day',
            'quantityNoun': 'animals',
            'quantity': 1,
            'pricePerUnit': 350.0,
            'total': 350.0,
          },
          'slaughtering_big': {
            'key': 'slaughtering_big',
            'label': 'Slaughtering Fees (Big Animals)',
            'unitLabel': 'Per animal',
            'quantityNoun': 'animals',
            'quantity': 1,
            'pricePerUnit': 1800.0,
            'total': 1800.0,
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await db.collection('farm_service_rates').doc(farmDoc.id).set(rates);
    } catch (e) {
      debugPrint('DemoReviewerService: service rates seed failed (non-fatal): $e');
    }

    // 6d. Trophy-stock inventory (`trophy_stock`) so the Trophy Registry +
    //     Trophy Stock Inventory screens show saleable quota.
    final trophyStock = <Map<String, dynamic>>[
      {
        'species': 'Greater Kudu',
        'availableCount': 3,
        'pricePerTrophyRands': 18500.0,
        'trophyMeasurement': 54.0,
        'trophyLengthInches': 54.0,
      },
      {
        'species': 'Cape Buffalo',
        'availableCount': 1,
        'pricePerTrophyRands': 125000.0,
        'trophyMeasurement': 42.0,
        'trophyLengthInches': 42.0,
      },
      {
        'species': 'Blesbok',
        'availableCount': 8,
        'pricePerTrophyRands': 4200.0,
      },
      {
        'species': 'Impala',
        'availableCount': 10,
        'pricePerTrophyRands': 3850.0,
      },
    ];
    for (final stock in trophyStock) {
      try {
        await db.collection('trophy_stock').add({
          ...stock,
          'farmId': farmDoc.id,
          'outfitterId': userId,
          'status': 'available',
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('DemoReviewerService: trophy stock seed failed (non-fatal): $e');
      }
    }

    // 6e. Published hunting package (`packages`) — a bookable 3-night kudu
    //     package with a real hunt window.
    try {
      final huntStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: 30));
      final huntEnd = huntStart.add(const Duration(days: 3));
      await db.collection('packages').add({
        'outfitterId': userId,
        'title': 'Waterberg Kudu Trophy Hunt (3 Nights)',
        'description': 'Guided 3-night kudu trophy hunt on Bosveld Demo '
            'Ranch. Includes daily guiding, farm vehicle, coldroom and '
            'overnight accommodation.',
        'basePriceRands': 24500.0,
        'totalPriceZAR': 24500.0,
        'inclusions': [
          'Farm guiding',
          'Bakkie / vehicle on the farm',
          'Coldroom storage',
          'Overnight accommodation (hunter)',
        ],
        'farmId': farmDoc.id,
        'farmName': 'Bosveld Demo Ranch',
        'imageUrls': <String>[],
        'quantityAvailable': 4,
        'mode': 'all_inclusive',
        'allInclusivePrice': 24500.0,
        'lineItems': List<Map<String, dynamic>>.empty(),
        'speciesItems': [
          {
            'speciesId': 'greater_kudu',
            'speciesName': 'Greater Kudu',
            'quantity': 1,
            'pricePerAnimal': 24500.0,
            'total': 24500.0,
          },
        ],
        'availabilityStart': Timestamp.fromDate(huntStart),
        'availabilityEnd': Timestamp.fromDate(huntEnd),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('DemoReviewerService: package seed failed (non-fatal): $e');
    }

    // 6f. Itemized farm price list (`farm_pricelists`) — the Custom Package
    //     Builder + farm-selection screens read these.
    final priceListEntries = <Map<String, dynamic>>[
      {
        'speciesName': 'Blesbok',
        'gender': 'Male',
        'hornTuskLength': '16"+',
        'qty': 10,
        'price': 4200.0,
      },
      {
        'speciesName': 'Impala',
        'gender': 'Male',
        'hornTuskLength': '23"+',
        'qty': 12,
        'price': 3850.0,
      },
      {
        'speciesName': 'Common Duiker',
        'gender': 'Male',
        'qty': 5,
        'price': 1450.0,
      },
      {
        'speciesName': 'Greater Kudu',
        'gender': 'Male',
        'hornTuskLength': '50"+',
        'qty': 3,
        'price': 18500.0,
      },
    ];
    for (final entry in priceListEntries) {
      try {
        await db.collection('farm_pricelists').add({
          ...entry,
          'farmId': farmDoc.id,
          'outfitterId': userId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('DemoReviewerService: price list seed failed (non-fatal): $e');
      }
    }

    // 6g. Client bookings (`bookings`) at different workflow stages so the
    //     Incoming Booking Requests dashboard + Financial Summary have data.
    //     The hunter-side uid is a separate demo "client" id; the outfitter
    //     party is the reviewer, so the dashboard query (`outfitterId ==
    //     uid`) + the booking rules (isBookingOutfitter) both admit it.
    const clientUid = 'demo-client-hunter-001';
    final bookingSamples = <Map<String, dynamic>>[
      {
        'packageId': 'CUSTOM_BUILT',
        'packageName': 'Custom Package · Bosveld Demo Ranch',
        'hunterId': clientUid,
        'status': BookingStatus.pendingApproval,
        'basePriceRands': 12450.0,
        'totalHunterPriceRands': 12450.0,
        'farmId': farmDoc.id,
        'isCustomPackage': true,
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      {
        'packageId': 'DEMO-PKG-001',
        'packageName': 'Waterberg Kudu Trophy Hunt (3 Nights)',
        'hunterId': clientUid,
        'status': BookingStatus.approvedAwaitingPayment,
        'basePriceRands': 24500.0,
        'totalHunterPriceRands': 24500.0,
        'farmId': farmDoc.id,
        'farmName': 'Bosveld Demo Ranch',
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      {
        'packageId': 'DEMO-PKG-002',
        'packageName': 'Blesbok Weekend Hunt',
        'hunterId': clientUid,
        'status': BookingStatus.confirmed,
        'basePriceRands': 8400.0,
        'totalHunterPriceRands': 8400.0,
        'farmId': farmDoc.id,
        'farmName': 'Bosveld Demo Ranch',
        'bookingTimestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    ];
    for (final booking in bookingSamples) {
      try {
        await db.collection('bookings').add({
          ...booking,
          'outfitterId': userId,
        });
      } catch (e) {
        debugPrint('DemoReviewerService: booking seed failed (non-fatal): $e');
      }
    }

    // 7. Track that seeding ran (purely informational; UI never depends on it).
    try {
      await db.collection('users').doc(userId).set({
        'demoSeedVersion': 2,
        'demoSeededAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal.
    }
  }

  /// Resets all injected test seams.
  @visibleForTesting
  void resetForTesting() {
    _authOverride = null;
    _firestoreOverride = null;
    _signInOverride = null;
    _enabledOverride = DemoReviewerConfig.enabled;
  }
}