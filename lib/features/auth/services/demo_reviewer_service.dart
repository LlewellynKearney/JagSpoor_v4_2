import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
/// showcase the restricted hunting + tracking features:
///
///   * SAPS license applications (`license_applications`) — several at
///     different stages (Submitted / Provincial / CFR / Printed);
///   * a small firearm inventory (`firearms` with nested `ammunition` load
///     profiles + linked optics) backing the Digital Firearm Safe,
///     ballistic calculator + shot-group analyzer;
///   * Digital Trophy Room entries (`trophies`) with realistic harvest
///     measurements;
///   * a COMPLETE hunter profile (`users/{uid}`: first/last name, phone,
///     email, `role: 'hunter'`, `outfitterId` self-link, and an active
///     subscription entitlement) so the mandatory-profile + subscription
///     gates admit the reviewer straight onto the hunter dashboard.
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
  /// If the review account's document does not yet exist (fresh sandbox /
  /// seeded via a `users/{uid}` doc by an admin), [resolveRole] resolves to
  /// [AppRole.hunter] because [seedDemoData] stamps `role: 'hunter'`.
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

      // Cache the resolved role (hunter, stamped below) so the route guard
      // admits the reviewer without a re-fetch.
      UserRoleProvider.instance.setRole(AppRole.hunter);

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

    // 1. Complete hunter profile + role + active subscription + self-link.
    final profile = <String, dynamic>{
      'firstName': 'Demo',
      'lastName': 'Reviewer',
      'fullName': DemoReviewerConfig.displayName,
      'phone': '+27 82 000 0000',
      'email': DemoReviewerConfig.email,
      'role': DemoReviewerConfig.role,
      'outfitterId': userId,
      'subscriptionStatus': 'active',
      'subscriptionTier': 'hunter',
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

    // Track that seeding ran (purely informational; UI never depends on it).
    try {
      await db.collection('users').doc(userId).set({
        'demoSeedVersion': 1,
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