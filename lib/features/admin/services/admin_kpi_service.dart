import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The Admin Portal headline metrics, computed SERVER-SIDE by the
/// `getAdminPortalKpis` Cloud Function.
///
/// Aggregating on the server is what makes these numbers trustworthy: several
/// of them span collections the client can only read with party-scoped rules
/// (`bookings`), and the install / Auth-user counts are not client-readable at
/// all. A client-side count silently returns 0 when a query is denied, which
/// is exactly the "Outfitters 2 / Listed Packages 0 / Bookings 0" symptom this
/// replaces.
class AdminPortalKpis {
  final int totalInstalls;
  final String installsSource; // 'installs' | 'authUsers'
  final int registeredUsers;
  final int totalSubscribers;
  final int payfastSubscribers;
  final int googleSubscribers;
  final int totalHunters;
  final int totalOutfitters;
  final int totalPackages;
  final int listedPackages;
  final int activeBookings;
  final int completedBookings;
  final int totalTrophies;
  final double dailyRevenue;
  final double weeklyRevenue;
  final double monthlyRevenue;
  final double yearlyRevenue;
  final double mrr;
  final double arr;
  final int hunterSubscribers;
  final int outfitterSubscribers;
  final double hunterPrice;
  final double outfitterPrice;

  const AdminPortalKpis({
    required this.totalInstalls,
    this.installsSource = 'authUsers',
    required this.registeredUsers,
    required this.totalSubscribers,
    required this.payfastSubscribers,
    required this.googleSubscribers,
    required this.totalHunters,
    required this.totalOutfitters,
    required this.totalPackages,
    required this.listedPackages,
    required this.activeBookings,
    required this.completedBookings,
    required this.totalTrophies,
    required this.dailyRevenue,
    required this.weeklyRevenue,
    required this.monthlyRevenue,
    required this.yearlyRevenue,
    required this.mrr,
    required this.arr,
    required this.hunterSubscribers,
    required this.outfitterSubscribers,
    required this.hunterPrice,
    required this.outfitterPrice,
  });

  /// True when the install figure came from a dedicated install beacon rather
  /// than the registered-account proxy, so the UI can label it honestly.
  bool get installsMeasured => installsSource == 'installs';

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0.0;
  }

  /// Parses the callable payload. Every field is defaulted so a partial /
  /// older server response renders rather than throwing.
  factory AdminPortalKpis.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    final financial = (data['financial'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return AdminPortalKpis(
      totalInstalls: _int(data['totalInstalls']),
      installsSource: (data['installsSource'] ?? 'authUsers').toString(),
      registeredUsers: _int(data['registeredUsers']),
      totalSubscribers: _int(data['totalSubscribers']),
      payfastSubscribers: _int(data['payfastSubscribers']),
      googleSubscribers: _int(data['googleSubscribers']),
      totalHunters: _int(data['totalHunters']),
      totalOutfitters: _int(data['totalOutfitters']),
      totalPackages: _int(data['totalPackages']),
      listedPackages: _int(data['listedPackages']),
      activeBookings: _int(data['activeBookings']),
      completedBookings: _int(data['completedBookings']),
      totalTrophies: _int(data['totalTrophies']),
      dailyRevenue: _double(financial['daily']),
      weeklyRevenue: _double(financial['weekly']),
      monthlyRevenue: _double(financial['monthly']),
      yearlyRevenue: _double(financial['yearly']),
      mrr: _double(financial['mrr']),
      arr: _double(financial['arr']),
      hunterSubscribers: _int(financial['hunterSubscribers']),
      outfitterSubscribers: _int(financial['outfitterSubscribers']),
      hunterPrice: _double(financial['hunterPrice']),
      outfitterPrice: _double(financial['outfitterPrice']),
    );
  }
}

/// Result of a server KPI fetch.
class AdminKpiResult {
  const AdminKpiResult({required this.kpis, required this.fromServer, this.error});

  final AdminPortalKpis? kpis;

  /// Whether the payload came from the `getAdminPortalKpis` callable (`true`)
  /// or the local fallback aggregation (`false`).
  final bool fromServer;

  /// Populated when the server call failed and the caller should be told the
  /// figures are locally computed.
  final String? error;
}

/// Reads the Admin Portal KPIs from the `getAdminPortalKpis` Cloud Function.
///
/// The callable is invoked over its HTTPS endpoint with the caller's Firebase
/// ID token, mirroring [EntitlementService.verifyGooglePlayPurchase] — no
/// extra platform plugin is required, so the Android / iOS / macOS builds are
/// untouched.
class AdminKpiService {
  AdminKpiService._();
  static final AdminKpiService instance = AdminKpiService._();

  static const String callableName = 'getAdminPortalKpis';
  static const String functionsRegion = 'us-central1';

  /// Test seams.
  @visibleForTesting
  static http.Client? httpClientForTesting;
  @visibleForTesting
  static Future<String?> Function()? idTokenResolverForTesting;
  @visibleForTesting
  static String projectIdForTesting = 'jagspoor';
  @visibleForTesting
  static void resetTestSeams() {
    httpClientForTesting = null;
    idTokenResolverForTesting = null;
    projectIdForTesting = 'jagspoor';
  }

  http.Client get _client => httpClientForTesting ?? http.Client();

  /// The callable endpoint URL.
  String get endpoint =>
      'https://$functionsRegion-$projectIdForTesting.cloudfunctions.net/$callableName';

  Future<String?> _idToken() async {
    final override = idTokenResolverForTesting;
    if (override != null) return override();
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null; // [core/no-app] during cold-launch / widget tests
    }
  }

  /// Fetches the server KPIs.
  ///
  /// Returns `null` KPIs with a human-readable [AdminKpiResult.error] when the
  /// caller is unauthenticated, the function is unreachable, or it answered an
  /// error — the caller then falls back to the local aggregation so the portal
  /// still renders. [forceRefresh] is forwarded to the server so a
  /// pull-to-refresh can bypass any server-side caching.
  Future<AdminKpiResult> fetchKpis({bool forceRefresh = false}) async {
    final idToken = await _idToken();
    if (idToken == null) {
      return const AdminKpiResult(
        kpis: null,
        fromServer: false,
        error: 'You must be signed in to load the portal KPIs.',
      );
    }
    try {
      final res = await _client.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {'forceRefresh': forceRefresh},
        }),
      );
      if (res.statusCode != 200) {
        return AdminKpiResult(
          kpis: null,
          fromServer: false,
          error: 'KPI service unavailable (${res.statusCode}).',
        );
      }
      final decoded = jsonDecode(res.body);
      // A callable wraps its result in `{ "result": ... }`; tolerate a bare
      // payload too so a proxy that unwraps it still works.
      final result = decoded is Map<String, dynamic>
          ? (decoded['result'] ?? decoded)
          : null;
      if (result is! Map) {
        return const AdminKpiResult(
          kpis: null,
          fromServer: false,
          error: 'KPI service returned an unexpected payload.',
        );
      }
      return AdminKpiResult(
        kpis: AdminPortalKpis.fromMap(result.cast<String, dynamic>()),
        fromServer: true,
      );
    } catch (e) {
      debugPrint('AdminKpiService.fetchKpis failed: $e');
      return AdminKpiResult(
        kpis: null,
        fromServer: false,
        error: 'KPI service unreachable.',
      );
    }
  }
}
