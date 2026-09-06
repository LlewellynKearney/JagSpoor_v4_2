import 'dart:math' as dart_math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/referral_conversion.dart';
import '../models/referral_profile.dart';
import '../models/referral_reward_config.dart';

/// Firestore repository for the JagSpoor referral system.
///
/// Owns every read/write against the three Phase-1 collections:
///  - `referral_profiles/{uid}`   — the user's profile (uid, unique code,
///    banking details).
///  - `referral_conversions/{id}` — who referred whom + tier + status.
///  - `admin_config/referral_rewards` — the dynamic hunter/outfitter reward
///    amounts.
///
/// All write methods resolve the current user lazily (never throws on a
/// cold-launch race) and every public operation is safe to call before
/// `Firebase.initializeApp()` — Firestore access short-circuits to a null /
/// empty result instead of throwing `[core/no-app]`.
class ReferralRepository {
  static final ReferralRepository instance =
      ReferralRepository._internal();

  ReferralRepository._internal({
    this.firestoreForTesting,
    this.currentUserIdResolverForTesting,
    this.randomForTesting,
  });

  /// Test seam: inject a Firestore instance (e.g. `FakeFirebaseFirestore`) so
  /// the query/write contract can be unit-tested without a live Firebase app.
  /// Defaults to the global instance.
  @visibleForTesting
  FirebaseFirestore? firestoreForTesting;

  FirebaseFirestore get _firestore =>
      firestoreForTesting ?? FirebaseFirestore.instance;

  /// Test seam: inject a uid resolver so the null-uid -> empty/error branches
  /// can be unit-tested without a real signed-in user. Defaults to the
  /// current Firebase user (null when no app is initialized / unauthenticated).
  @visibleForTesting
  String? Function()? currentUserIdResolverForTesting;

  String? get _currentUserId {
    if (currentUserIdResolverForTesting != null) {
      return currentUserIdResolverForTesting!();
    }
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
    }
    return null;
  }

  /// Test seam: inject a `Random` so referral-code generation is
  /// deterministic in tests. Defaults to a fresh `Random()`.
  @visibleForTesting
  dart_math.Random? randomForTesting;

  /// Test-only constructor: build a fresh, isolated repository bound to an
  /// injectable Firestore + uid resolver (mirrors the `FarmGamePriceList
  /// Manager.forTesting` / `OpticLogService.forTesting` pattern).
  @visibleForTesting
  factory ReferralRepository.forTesting({
    required FirebaseFirestore firestore,
    required String? Function() currentUserIdResolver,
    dart_math.Random? random,
  }) =>
      ReferralRepository._internal(
        firestoreForTesting: firestore,
        currentUserIdResolverForTesting: currentUserIdResolver,
        randomForTesting: random,
      );

  /// Generates a random, human-friendly referral code of [length] characters
  /// from [kReferralCodeAlphabet]. Pure + testable via the injected `Random`.
  static String generateReferralCode({int length = 8, dart_math.Random? random}) {
    final rng = random ?? dart_math.Random();
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(kReferralCodeAlphabet[rng.nextInt(kReferralCodeAlphabet.length)]);
    }
    return sb.toString();
  }

  /// Public seam accessor (used by the profile-creation write).
  dart_math.Random get _random => randomForTesting ?? dart_math.Random();

  // ── referral_profiles ────────────────────────────────────────────────────

  /// Fetches the current user's referral profile, or null when absent.
  Future<ReferralProfile?> getMyReferralProfile() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return null;
    try {
      final snap =
          await _firestore.collection(kReferralProfilesCollection).doc(uid).get();
      if (!snap.exists) return null;
      return ReferralProfile.fromMap(snap.data() ?? const <String, dynamic>{},
          id: snap.id);
    } catch (e) {
      debugPrint('ReferralRepository.getMyReferralProfile: $e');
      return null;
    }
  }

  /// Fetches a user's referral profile by their UID (used to resolve the
  /// referrer when a new signup redeems a code). Returns null when absent.
  Future<ReferralProfile?> getReferralProfile(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final snap =
          await _firestore.collection(kReferralProfilesCollection).doc(userId).get();
      if (!snap.exists) return null;
      return ReferralProfile.fromMap(snap.data() ?? const <String, dynamic>{},
          id: snap.id);
    } catch (e) {
      debugPrint('ReferralRepository.getReferralProfile: $e');
      return null;
    }
  }

  /// Creates the current user's referral profile.
  ///
  /// Generates a unique code ([generateReferralCode], 8 chars by default)
  /// and writes `referral_profiles/{uid}` (owner-scoped per
  /// `firestore.rules`). Merges when a profile doc already exists so an
  /// idempotent retry never clobbers the banking details.
  ///
  /// Throws [StateError] when the caller is unauthenticated. The uniqueness
  /// assertion is best-effort: a code collision surfaces as a Firestore
  /// write error (the `referral_code_unique` property denies the write), and
  /// the caller can retry.
  Future<ReferralProfile> createMyReferralProfile({
    int codeLength = 8,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to create a referral profile.');
    }
    final code = generateReferralCode(length: codeLength, random: _random);
    await _firestore
        .collection(kReferralProfilesCollection)
        .doc(uid)
        .set(
          {
            'userId': uid,
            'referralCode': code,
            'bankingDetailsProvided': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
    return ReferralProfile(
      userId: uid,
      referralCode: code,
      bankingDetailsProvided: false,
    );
  }

  /// Loads the current user's referral profile, generating + persisting a
  /// unique code when none exists yet (the Phase-3 "auto-generate or load"
  /// contract used by the share widgets).
  ///
  /// Returns the existing profile when one is present; otherwise
  /// [createMyReferralProfile] is invoked (idempotent merge) and the freshly
  /// generated profile is returned. Returns null when the caller is
  /// unauthenticated or the Firestore read/write fails (never throws).
  Future<ReferralProfile?> getOrCreateMyReferralProfile() async {
    final existing = await getMyReferralProfile();
    if (existing != null && existing.referralCode.isNotEmpty) {
      return existing;
    }
    try {
      return await createMyReferralProfile();
    } catch (e) {
      debugPrint('ReferralRepository.getOrCreateMyReferralProfile: $e');
      return null;
    }
  }

  /// Updates the current user's banking payout details on their profile
  /// (merge-write). Passing an empty field clears it (stored as `null` via
  /// `FieldValue.delete` so a later `bankingDetailsProvided` read stays
  /// false-consistent).
  ///
  /// Throws [StateError] when the caller is unauthenticated.
  Future<void> updateMyBankingDetails({
    String bankAccountHolder = '',
    String bankName = '',
    String bankAccountNumber = '',
    String bankAccountType = '',
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to update banking details.');
    }
    final updates = <String, dynamic>{
      'bankingDetailsProvided':
          bankAccountHolder.isNotEmpty && bankAccountNumber.isNotEmpty,
    };
    _putStringOrDelete(updates, 'bankAccountHolder', bankAccountHolder);
    _putStringOrDelete(updates, 'bankName', bankName);
    _putStringOrDelete(updates, 'bankAccountNumber', bankAccountNumber);
    _putStringOrDelete(updates, 'bankAccountType', bankAccountType);
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection(kReferralProfilesCollection)
        .doc(uid)
        .set(updates, SetOptions(merge: true));
  }

  // ── referral_conversions ─────────────────────────────────────────────────

  /// Records a referral conversion: the [referrerId] whose code [referralCode]
  /// was redeemed by the newly-created account [referredUserId] at
  /// [subscriptionTier]. Status starts at [ReferralConversionStatus.pending]
  /// (a qualifying action must still complete); the TypeScript backend
  /// finalises the reward (`rewarded`/`rejected` + `rewardAmountZAR`) when
  /// the referred user's subscription activates (Phase 2 wires the trigger).
  ///
  /// The write is owner-agnostic server-side (any signed-in user may create
  /// per `firestore.rules` — the client validates referrer != referred).
  Future<String> recordConversion({
    required String referrerId,
    required String referredUserId,
    required String referralCode,
    ReferralSubscriptionTier subscriptionTier =
        ReferralSubscriptionTier.hunter,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to record a referral conversion.');
    }
    if (referrerId.isEmpty) {
      throw ArgumentError('referrerId is required.');
    }
    if (referredUserId.isEmpty) {
      throw ArgumentError('referredUserId is required.');
    }
    if (referrerId == referredUserId) {
      throw StateError('A user cannot refer themself.');
    }
    final code = referralCode.trim().toUpperCase();
    if (code.isEmpty) {
      throw ArgumentError('referralCode is required.');
    }
    final doc =
        _firestore.collection(kReferralConversionsCollection).doc();
    await doc.set({
      'referrerId': referrerId,
      'referredUserId': referredUserId,
      'referralCode': code,
      'subscriptionTier': subscriptionTier.key,
      'status': ReferralConversionStatus.pending.key,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Fetches every conversion where the current user is the referrer
  /// (newest-first). Returns an empty list for an unauthenticated caller.
  Future<List<ReferralConversion>> getConversionsForCurrentUser() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection(kReferralConversionsCollection)
          .where('referrerId', isEqualTo: uid)
          .get();
      final conversions =
          snap.docs.map(ReferralConversion.fromFirestore).toList();
      conversions.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return conversions;
    } catch (e) {
      debugPrint('ReferralRepository.getConversionsForCurrentUser: $e');
      return const [];
    }
  }

  /// Fetches a single conversion by id. Returns null when absent/unreadable.
  Future<ReferralConversion?> getConversion(String conversionId) async {
    if (conversionId.isEmpty) return null;
    try {
      final snap = await _firestore
          .collection(kReferralConversionsCollection)
          .doc(conversionId)
          .get();
      if (!snap.exists) return null;
      return ReferralConversion.fromFirestore(snap);
    } catch (e) {
      debugPrint('ReferralRepository.getConversion: $e');
      return null;
    }
  }

  // ── admin_config ─────────────────────────────────────────────────────────

  /// Loads the dynamic admin reward configuration. Falls back to the
  /// documented defaults in [ReferralRewardConfig.fromMap] when the document
  /// is absent or unreadable (never throws).
  Future<ReferralRewardConfig> loadRewardConfig() async {
    try {
      final snap = await _firestore
          .collection(kAdminConfigCollection)
          .doc(ReferralRewards.adminConfigDocId)
          .get();
      return ReferralRewardConfig.fromMap(snap.data());
    } catch (e) {
      debugPrint('ReferralRepository.loadRewardConfig: $e');
      return const ReferralRewardConfig();
    }
  }

  /// Persists the dynamic admin reward configuration to
  /// `admin_config/referral_rewards` (merge, so other `admin_config`
  /// fields are preserved). Negative amounts are clamped to zero so a
  /// misconfiguration can never persist a negative reward — the same
  /// sanitisation contract as [ReferralRewardConfig.fromMap] /
  /// `SubscriptionConfigService.saveConfig`. Admin-write per
  /// `firestore.rules` (`admin_config` write is admin-only).
  Future<void> saveRewardConfig(ReferralRewardConfig config) async {
    final sanitized = ReferralRewardConfig(
      hunterRewardZAR: config.hunterRewardZAR < 0
          ? 0.0
          : config.hunterRewardZAR,
      outfitterRewardZAR: config.outfitterRewardZAR < 0
          ? 0.0
          : config.outfitterRewardZAR,
    );
    await _firestore
        .collection(kAdminConfigCollection)
        .doc(ReferralRewards.adminConfigDocId)
        .set(sanitized.toMap(), SetOptions(merge: true));
  }

  static void _putStringOrDelete(
    Map<String, dynamic> updates,
    String field,
    String value,
  ) {
    if (value.trim().isEmpty) {
      updates[field] = FieldValue.delete();
    } else {
      updates[field] = value.trim();
    }
  }
}