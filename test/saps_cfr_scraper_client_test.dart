import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_cfr_scraper_client.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_tracker_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  group('SapsCfrScraperClient', () {
    test('isConfigured reflects the webhook URL', () {
      expect(SapsCfrScraperClient().isConfigured, isFalse);
      expect(
        SapsCfrScraperClient(webhookUrl: 'https://example.com/hook')
            .isConfigured,
        isTrue,
      );
    });

    test('fetchStatus POSTs reference + id and parses the raw status',
        () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'status': 'Sent to Provincial DFO', 'message': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = SapsCfrScraperClient(
        webhookUrl: 'https://hook.example.com/cfr',
        httpClient: mock,
      );
      final result = await client.fetchStatus(
        referenceNumber: 'REF-1',
        idNumber: '9001015009087',
      );

      expect(result, isNotNull);
      expect(result!.rawStatus, 'Sent to Provincial DFO');
      expect(result.statusMessage, 'ok');

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://hook.example.com/cfr');
      final body = jsonDecode(captured.body);
      expect(body['referenceNumber'], 'REF-1');
      expect(body['idNumber'], '9001015009087');
    });

    test('fetchStatus returns null on a non-200 response (never throws)',
        () async {
      final mock = MockClient(
        (request) async => http.Response('gateway error', 502),
      );
      final client = SapsCfrScraperClient(
        webhookUrl: 'https://hook.example.com/cfr',
        httpClient: mock,
      );
      expect(
        await client.fetchStatus(
          referenceNumber: 'REF-1',
          idNumber: '9001015009087',
        ),
        isNull,
      );
    });

    test('fetchStatus returns null on an unparseable payload', () async {
      final mock = MockClient(
        (request) async => http.Response('<html>not json</html>', 200),
      );
      final client = SapsCfrScraperClient(
        webhookUrl: 'https://hook.example.com/cfr',
        httpClient: mock,
      );
      expect(
        await client.fetchStatus(
          referenceNumber: 'REF-1',
          idNumber: '9001015009087',
        ),
        isNull,
      );
    });

    test('fetchStatus refuses when the webhook is not configured', () async {
      final client = SapsCfrScraperClient();
      expect(
        await client.fetchStatus(
          referenceNumber: 'REF-1',
          idNumber: '9001015009087',
        ),
        isNull,
      );
    });
  });

  group('SapsTrackerService webhook integration', () {
    test('uses the CFR webhook status when a configured scraper is supplied',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('license_applications').doc('app-1').set({
        'hunterId': 'u1',
        'referenceNumber': 'REF-1',
        'idNumber': '9001015009087',
      });

      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({'status': 'Received at the CFR'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final scraper = SapsCfrScraperClient(
        webhookUrl: 'https://hook.example.com/cfr',
        httpClient: mock,
      );
      final service = SapsTrackerService.forTesting(fake, scraper: scraper);

      final result = await service.triggerRemoteScraperCheck('app-1');
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.status, 'Received at the CFR');
      // CFR stage (2), NOT a mock DFO stage -> proves the webhook path ran.
      expect(result.statusCode, 2);
    });

    test('falls back to the offline mock when no webhook is configured',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('license_applications').doc('app-1').set({
        'hunterId': 'u1',
        'referenceNumber': 'REF-1',
        'idNumber': '9001015009087',
      });
      final service = SapsTrackerService.forTesting(fake);

      final result = await service.triggerRemoteScraperCheck('app-1');
      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(result.status, isNotEmpty);
    });

    test('handles a failing webhook gracefully (null, never throws)',
        () async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('license_applications').doc('app-1').set({
        'hunterId': 'u1',
        'referenceNumber': 'REF-1',
        'idNumber': '9001015009087',
      });
      final mock = MockClient(
        (request) async => http.Response('boom', 500),
      );
      final scraper = SapsCfrScraperClient(
        webhookUrl: 'https://hook.example.com/cfr',
        httpClient: mock,
      );
      final service = SapsTrackerService.forTesting(fake, scraper: scraper);

      final result = await service.triggerRemoteScraperCheck('app-1');
      expect(result, isNull);
    });
  });
}