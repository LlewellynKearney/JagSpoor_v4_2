// ============================================================================
// Admin Portal KPIs — client service contract
//
// The dashboard reads its headline metrics from the `getAdminPortalKpis`
// Cloud Function (server-side aggregation) and falls back to local estimates
// when the callable is unreachable. These tests lock the payload parsing, the
// fallback contract, and the callable request shape.
// ============================================================================
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:jagspoor/features/admin/services/admin_kpi_service.dart';

/// A representative server payload, matching `AdminKpis` in
/// functions/src/admin/kpis.ts.
Map<String, dynamic> serverPayload() => {
      'totalInstalls': 120,
      'installsSource': 'installs',
      'registeredUsers': 25,
      'totalSubscribers': 16,
      'payfastSubscribers': 4,
      'googleSubscribers': 12,
      'totalHunters': 14,
      'totalOutfitters': 2,
      'totalPackages': 6,
      'listedPackages': 5,
      'activeBookings': 7,
      'completedBookings': 3,
      'totalTrophies': 19,
      'financial': {
        'daily': 0.0,
        'weekly': 0.0,
        'monthly': 12000.0,
        'yearly': 48000.0,
        'mrr': 1089.84,
        'arr': 13078.08,
        'hunterSubscribers': 14,
        'outfitterSubscribers': 2,
        'hunterPrice': 34.99,
        'outfitterPrice': 299.99,
      },
      'generatedAt': '2026-10-30T12:00:00.000Z',
    };

void main() {
  setUp(() {
    AdminKpiService.resetTestSeams();
  });
  tearDown(() {
    AdminKpiService.resetTestSeams();
  });

  group('AdminPortalKpis.fromMap', () {
    test('parses a full server payload', () {
      final kpis = AdminPortalKpis.fromMap(serverPayload());
      expect(kpis.totalInstalls, 120);
      expect(kpis.installsSource, 'installs');
      expect(kpis.installsMeasured, isTrue);
      expect(kpis.registeredUsers, 25);
      expect(kpis.totalSubscribers, 16);
      expect(kpis.payfastSubscribers, 4);
      expect(kpis.googleSubscribers, 12);
      expect(kpis.totalHunters, 14);
      expect(kpis.totalOutfitters, 2);
      expect(kpis.totalPackages, 6);
      expect(kpis.listedPackages, 5);
      expect(kpis.activeBookings, 7);
      expect(kpis.completedBookings, 3);
      expect(kpis.totalTrophies, 19);
      expect(kpis.mrr, 1089.84);
      expect(kpis.arr, 13078.08);
      expect(kpis.hunterSubscribers, 14);
      expect(kpis.outfitterSubscribers, 2);
      expect(kpis.hunterPrice, 34.99);
      expect(kpis.outfitterPrice, 299.99);
    });

    test('defaults every field for a partial / older payload', () {
      final kpis = AdminPortalKpis.fromMap(const {'registeredUsers': 3});
      expect(kpis.registeredUsers, 3);
      expect(kpis.totalInstalls, 0);
      expect(kpis.mrr, 0.0);
      // A missing installsSource falls back to the account proxy and is NOT
      // reported as measured.
      expect(kpis.installsSource, 'authUsers');
      expect(kpis.installsMeasured, isFalse);
    });

    test('tolerates null and numeric strings', () {
      final kpis = AdminPortalKpis.fromMap(const {
        'registeredUsers': '25',
        'financial': {'mrr': '1089.84'},
      });
      expect(kpis.registeredUsers, 25);
      expect(kpis.mrr, 1089.84);
      expect(AdminPortalKpis.fromMap(null).registeredUsers, 0);
    });
  });

  group('AdminKpiService.fetchKpis', () {
    test('POSTs to the callable with the ID token and parses the result',
        () async {
      Uri? capturedUri;
      String? capturedAuth;
      Map<String, dynamic>? capturedBody;

      AdminKpiService.idTokenResolverForTesting = () async => 'id-token-abc';
      AdminKpiService.httpClientForTesting = MockClient((request) async {
        capturedUri = request.url;
        capturedAuth = request.headers['Authorization'];
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'result': serverPayload()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await AdminKpiService.instance.fetchKpis();

      expect(capturedUri.toString(),
          'https://us-central1-jagspoor.cloudfunctions.net/getAdminPortalKpis');
      expect(capturedAuth, 'Bearer id-token-abc');
      expect(capturedBody!['data']['forceRefresh'], isFalse);
      expect(result.fromServer, isTrue);
      expect(result.error, isNull);
      expect(result.kpis!.totalSubscribers, 16);
      expect(result.kpis!.mrr, 1089.84);
    });

    test('forwards forceRefresh for a pull-to-refresh', () async {
      Map<String, dynamic>? capturedBody;
      AdminKpiService.idTokenResolverForTesting = () async => 'tok';
      AdminKpiService.httpClientForTesting = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'result': serverPayload()}), 200);
      });

      await AdminKpiService.instance.fetchKpis(forceRefresh: true);
      expect(capturedBody!['data']['forceRefresh'], isTrue);
    });

    test('reports a signed-out caller without a network call', () async {
      var called = false;
      AdminKpiService.idTokenResolverForTesting = () async => null;
      AdminKpiService.httpClientForTesting = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });

      final result = await AdminKpiService.instance.fetchKpis();
      expect(called, isFalse);
      expect(result.fromServer, isFalse);
      expect(result.kpis, isNull);
      expect(result.error, contains('signed in'));
    });

    test('degrades gracefully on a non-200 response', () async {
      AdminKpiService.idTokenResolverForTesting = () async => 'tok';
      AdminKpiService.httpClientForTesting =
          MockClient((_) async => http.Response('denied', 403));

      final result = await AdminKpiService.instance.fetchKpis();
      expect(result.fromServer, isFalse);
      expect(result.kpis, isNull);
      expect(result.error, contains('403'));
    });

    test('degrades gracefully when the endpoint is unreachable', () async {
      AdminKpiService.idTokenResolverForTesting = () async => 'tok';
      AdminKpiService.httpClientForTesting =
          MockClient((_) async => throw Exception('socket closed'));

      final result = await AdminKpiService.instance.fetchKpis();
      expect(result.fromServer, isFalse);
      expect(result.error, contains('unreachable'));
    });

    test('tolerates a bare (unwrapped) payload', () async {
      AdminKpiService.idTokenResolverForTesting = () async => 'tok';
      AdminKpiService.httpClientForTesting = MockClient(
          (_) async => http.Response(jsonEncode(serverPayload()), 200));

      final result = await AdminKpiService.instance.fetchKpis();
      expect(result.fromServer, isTrue);
      expect(result.kpis!.registeredUsers, 25);
    });

    test('rejects an unexpected payload shape', () async {
      AdminKpiService.idTokenResolverForTesting = () async => 'tok';
      AdminKpiService.httpClientForTesting =
          MockClient((_) async => http.Response(jsonEncode({'result': 7}), 200));

      final result = await AdminKpiService.instance.fetchKpis();
      expect(result.fromServer, isFalse);
      expect(result.error, contains('unexpected payload'));
    });
  });
}
