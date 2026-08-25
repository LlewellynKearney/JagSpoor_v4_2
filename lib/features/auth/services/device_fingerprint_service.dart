import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Hardware-level device fingerprinting for trial-abuse prevention.
///
/// The fingerprint is a SHA-256 hash of the platform's hardware-backed
/// identifier:
///  - Android: `Settings.Secure.ANDROID_ID` (survives app reinstalls; tied
///    to the physical device).
///  - iOS: `identifierForVendor` (per-vendor stable id stored at the device
///    level).
///
/// Combined with manufacturer + model so a collision between the builtin
/// Android ID fallback and other vendors is impossible.
///
/// The backend `initializeNewUserTrial` Auth onCreate trigger reads the
/// `deviceFingerprint` field on `users/{uid}` and blocks the free trial
/// (fail-closed) when another user doc already carries the same fingerprint,
/// so a malicious user cannot spin up infinite trial accounts on the same
/// physical device.
class DeviceFingerprintService {
  DeviceFingerprintService._();

  /// Process-wide singleton.
  static final DeviceFingerprintService instance = DeviceFingerprintService._();

  // --- Test seams ------------------------------------------------------------
  // The resolver seam returns a synthetic fingerprint in widget/unit tests
  // without touching the device_info plugin; the write seam intercepts the
  // Firestore merge so no Firebase app is required.
  @visibleForTesting
  static Future<String?> Function()? fingerprintResolverForTesting;
  @visibleForTesting
  static Future<void> Function(String uid, String fingerprint)?
      stampWriterForTesting;

  @visibleForTesting
  static void resetTestSeams() {
    fingerprintResolverForTesting = null;
    stampWriterForTesting = null;
  }

  // --- Production operations -------------------------------------------------

  /// Computes the device fingerprint, or null when the current platform has
  /// no hardware-backed identifier (e.g. web/desktop host or plugin error).
  /// Never throws — an unavailable fingerprint resolves to null (the backend
  /// treats missing fingerprints as a fail-closed block).
  Future<String?> computeFingerprint() async {
    if (fingerprintResolverForTesting != null) {
      try {
        return await fingerprintResolverForTesting!();
      } catch (_) {
        return null;
      }
    }
    try {
      String? baseId;
      String? model;
      String? manufacturer;
      if (kIsWeb) return null;
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        baseId = info.id;
        model = info.model;
        manufacturer = info.manufacturer;
      } else if (Platform.isIOS) {
        final info = await DeviceInfoPlugin().iosInfo;
        baseId = info.identifierForVendor;
        model = info.model;
        manufacturer = 'Apple';
      } else {
        return null;
      }
      if (baseId == null || baseId.isEmpty) return null;
      final raw = '$baseId|$manufacturer|$model';
      return sha256.convert(utf8.encode(raw)).toString();
    } catch (e) {
      debugPrint('DeviceFingerprintService: fingerprint unavailable: $e');
      return null;
    }
  }

  /// Stamps the device fingerprint onto `users/{uid}` (merge-write), so the
  /// backend trial-initialization trigger can read it at account-creation
  /// time. Failures are logged and never block registration/sign-in (the
  /// backend treats a missing fingerprint as a fail-closed block, so a user
  /// who cannot write one correctly gets no free trial).
  Future<void> stampDeviceFingerprint(String userId) async {
    if (userId.trim().isEmpty) return;
    final fingerprint = await computeFingerprint();
    if (fingerprint == null || fingerprint.isEmpty) return;
    if (stampWriterForTesting != null) {
      await stampWriterForTesting!(userId, fingerprint);
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'deviceFingerprint': fingerprint,
          'deviceFingerprintUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('DeviceFingerprintService: stamp write failed: $e');
    }
  }

  /// Static convenience wrapper (mirrors the project's service API style).
  static Future<String?> currentFingerprint() =>
      instance.computeFingerprint();
}
