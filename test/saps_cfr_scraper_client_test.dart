import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_cfr_scraper_client.dart';
import 'package:jagspoor/features/hunter_mode/services/saps_status_classifier.dart';
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

    test('debug build with no webhook uses the direct portal path', () async {
      // In a kDebugMode test run (which this is), a client with no webhook
      // configured performs the real device -> portal enquiry. Drive it with
      // a mocked transport so no live network is touched: the GET returns the
      // form (csrf token + cookie) and the POST returns the NOT_FOUND page.
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '<input type="hidden" name="csrf" value="tok123">',
            200,
            headers: {'set-cookie': 'csrf_token=cook123; path=/; HttpOnly'},
          );
        }
        expect(request.url.toString(),
            'https://www.saps.gov.za/services/firearm_status_enquiry.php');
        final body = request.body;
        // The POST must carry ALL six enquiry fields.
        expect(body, contains('fsref=10470664'));
        expect(body, contains('fref=10470664'));
        expect(body, contains('fserial=OB14468'));
        expect(body, contains('fiserial=OB14468'));
        expect(body, contains('fid='));
        expect(body, contains('frid='));
        return http.Response(
          '<i>The data on this page were updated on <b>2026-10-10</b>.</i>'
          '<table><tr><td colspan="9">No records to retrieve for your '
          'selected Reference Number (10470664) and Serial Number '
          '(OB14468) ...</td></tr></table>',
          200,
        );
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      expect(client.isConfigured, isFalse);
      expect(client.isDirectDebugEnabled, isTrue);

      final result = await client.fetchStatus(
        referenceNumber: '10470664',
        idNumber: '9001015009087',
        serialNumber: 'OB14468',
      );
      expect(result, isNotNull);
      expect(result!.notFound, isTrue);
      expect(result.stage, -1);
      expect(result.sapsUpdatedAt, DateTime.parse('2026-10-10'));
    });

    test('GET-first: a usable results page is parsed without a POST',
        () async {
      var postCount = 0;
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          // The query-parameter GET carries ALL six fields (ref duplicated
          // into fsref/fref, serial into fserial/fiserial) and returns the
          // results page directly.
          expect(request.url.queryParameters['fsref'], '10654672');
          expect(request.url.queryParameters['fref'], '10654672');
          expect(request.url.queryParameters['fserial'], 'OB14468');
          expect(request.url.queryParameters['fiserial'], 'OB14468');
          expect(request.url.queryParameters.containsKey('fid'), isTrue);
          expect(request.url.queryParameters.containsKey('frid'), isTrue);
          return http.Response(
            '<b>Search Results:</b><table>'
            '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
            '<td>9001015009087</td><td>6MM MUSGRAVE</td><td>TIKKA T3X</td>'
            '<td>OB14468</td><td>2026-10-01</td>'
            '<td>Received at Licensing Section</td>'
            '<td>For consideration by the Commissioner</td>'
            '<td>Await decision</td></tr></table>',
            200,
          );
        }
        postCount++;
        return http.Response('should not be reached', 500);
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: 'OB14468',
      );
      expect(result, isNotNull);
      expect(result!.applicationNumber, '10654672');
      expect(result.stage, 2);
      expect(postCount, 0, reason: 'GET-first must not POST on success');
    });

    test('GET-first falls back to POST when the query GET has no results',
        () async {
      var posted = false;
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          // The GET returns the "Please supply" page (no results table), so it
          // must be treated as empty and force the POST.
          return http.Response(
            '<input type="hidden" name="csrf" value="tok">'
            '<div>Please supply a Serial Number AND Reference Number</div>',
            200,
            headers: {'set-cookie': 'csrf_token=cook; path=/'},
          );
        }
        posted = true;
        // The POST must carry ALL six fields plus the csrf handshake.
        expect(request.body, contains('fsref=10654672'));
        expect(request.body, contains('fref=10654672'));
        expect(request.body, contains('fserial=OB14468'));
        expect(request.body, contains('fiserial=OB14468'));
        expect(request.body, contains('fid='));
        expect(request.body, contains('frid='));
        expect(request.body, contains('csrf=tok'));
        return http.Response(
          '<table><tr><td colspan="9">No records to retrieve ...</td></tr>'
          '</table>',
          200,
        );
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: 'OB14468',
      );
      expect(posted, isTrue, reason: 'a no-results GET must force the POST');
      expect(result, isNotNull);
      expect(result!.notFound, isTrue);
    });

    test('GET with all six params is used and only a results table is accepted',
        () {
      final uri = SapsCfrScraperClient.buildQueryEnquiryUri(
        referenceNumber: '10654672',
        serialNumber: 'OB14468',
      );
      expect(uri.queryParameters['fsref'], '10654672');
      expect(uri.queryParameters['fref'], '10654672');
      expect(uri.queryParameters['fserial'], 'OB14468');
      expect(uri.queryParameters['fiserial'], 'OB14468');
      expect(uri.queryParameters['fid'], '');
      expect(uri.queryParameters['frid'], '');
      // The six-field body shares the same shape (csrf appended by callers).
      final fields = SapsCfrScraperClient.enquiryFormFields(
        referenceNumber: '10654672',
        serialNumber: 'OB14468',
      );
      expect(fields['fsref'], '10654672');
      expect(fields['fref'], '10654672');
      expect(fields['fserial'], 'OB14468');
      expect(fields['fiserial'], 'OB14468');
      expect(fields['fid'], '');
      expect(fields['frid'], '');
    });

    test('a bare DOCTYPE page with no results table forces the POST',
        () async {
      var getCount = 0;
      var posted = false;
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          getCount++;
          return http.Response(
            '<!DOCTYPE html><html><body>'
            '<input type="hidden" name="csrf" value="tok">'
            '</body></html>',
            200,
            headers: {'set-cookie': 'csrf_token=cook; path=/'},
          );
        }
        posted = true;
        return http.Response(
          '<b>Search Results:</b><table>'
          '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
          '<td>9001015009087</td><td>6MM MUSGRAVE</td><td>TIKKA T3X</td>'
          '<td>OB14468</td><td>2026-10-01</td>'
          '<td>Received at Licensing Section</td>'
          '<td>For consideration by the Commissioner</td>'
          '<td>Await decision</td></tr></table>',
          200,
        );
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: 'OB14468',
      );
      expect(getCount, greaterThanOrEqualTo(2),
          reason: 'query GET + form GET before the POST');
      expect(posted, isTrue);
      expect(result, isNotNull);
      expect(result!.applicationNumber, '10654672');
    });

    test('POST 303 follows the Location header then parses the results',
        () async {
      var redirected = false;
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response('', 303, headers: {
            'location': '/services/firearm_status_results.php',
          });
        }
        // GETs: form (with csrf), then the redirect target.
        if (request.url.path.contains('firearm_status_results')) {
          redirected = true;
          return http.Response(
            '<b>Search Results:</b><table>'
            '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
            '<td>9001015009087</td><td>6MM MUSGRAVE</td><td>TIKKA T3X</td>'
            '<td>OB14468</td><td>2026-10-01</td>'
            '<td>Received at Licensing Section</td>'
            '<td>For consideration by the Commissioner</td>'
            '<td>Await decision</td></tr></table>',
            200,
          );
        }
        return http.Response(
          '<input type="hidden" name="csrf" value="tok">'
          '<div>Please supply a Serial Number AND Reference Number</div>',
          200,
          headers: {'set-cookie': 'csrf_token=cook; path=/'},
        );
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: 'OB14468',
      );
      expect(redirected, isTrue, reason: '303 Location must be followed');
      expect(result, isNotNull);
      expect(result!.applicationNumber, '10654672');
    });

    test('parses the NEED_SERIAL_AND_REF validation prompt end-to-end',
        () async {
      // The GET has no results table -> the POST is forced. The POST response
      // carries the "Please supply" banner (still no results table), so the
      // parse surfaces the actionable NEED_SERIAL prompt.
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '<input type="hidden" name="csrf" value="tok">'
            '<div>Please supply a Serial Number AND Reference Number</div>',
            200,
            headers: {'set-cookie': 'csrf_token=cook; path=/'},
          );
        }
        return http.Response(
          '<i>The data on this page were updated on <b>2026-10-10</b>.</i>'
          '<div>Please supply a Serial Number AND Reference Number</div>',
          200,
        );
      });

      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: '',
      );
      expect(result, isNotNull);
      expect(result!.stage, -2);
      expect(result.rawStatus, SapsCfrScraperClient.kNeedSerialAndRefStatus);
      // The portal banner date is still captured.
      expect(result.sapsUpdatedAt, DateTime.parse('2026-10-10'));
      expect(result.htmlSnippet, isNotEmpty);
    });

    test('a results table wins even when the Please-supply banner is present',
        () {
      const html =
          '<div>Please supply a Serial Number AND Reference Number</div>'
          '<b>Search Results:</b><table>'
          '<tr><td>Section 16 Dedicated Hunting</td><td>10654672</td>'
          '<td>9001015009087</td><td>6MM MUSGRAVE</td><td>TIKKA T3X</td>'
          '<td>OB14468</td><td>2026-10-01</td>'
          '<td>Received at Licensing Section</td>'
          '<td>For consideration by the Commissioner</td>'
          '<td>Await decision</td></tr></table>';
      final status = SapsCfrScraperClient.parseEnquiryPage(html);
      expect(status, isNotNull);
      expect(status!.applicationNumber, '10654672');
      expect(status.stage, isNot(kSapsStageNeedSerialAndRef));
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

  group('SapsCfrScraperClient cert bypass (Android debug) ', () {
    test('bypasses certificate verification for saps.gov.za', () {
      // The test runner is a debug build, so certBypassForHost mirrors the
      // production kDebugMode behaviour.
      expect(
        SapsCfrScraperClient.certBypassForHost('www.saps.gov.za'),
        isTrue,
      );
      expect(
        SapsCfrScraperClient.certBypassForHost('saps.gov.za'),
        isTrue,
      );
    });

    test('does NOT bypass certificate verification for other hosts', () {
      // The host gate is the security boundary — every non-SAPS host keeps
      // full verification even in a debug build.
      expect(
        SapsCfrScraperClient.certBypassForHost('example.com'),
        isFalse,
      );
      expect(
        SapsCfrScraperClient.certBypassForHost('gov.za.evil.example'),
        isFalse,
      );
      expect(
        SapsCfrScraperClient.certBypassForHost('hook.example.com'),
        isFalse,
      );
    });

    test('an injected client still drives the direct portal path', () async {
      // Regression guard: the test seam must win over the cert-bypass client,
      // so a mocked transport never reaches the live portal.
      var getCount = 0;
      final mock = MockClient((request) async {
        getCount++;
        return http.Response(
          '<i>updated on <b>2026-10-10</b></i>'
          '<div>Please supply a Serial Number AND Reference Number</div>',
          200,
        );
      });
      final client = SapsCfrScraperClient(httpClient: mock);
      final result = await client.fetchStatus(
        referenceNumber: '10654672',
        idNumber: '',
        serialNumber: '',
      );
      expect(result, isNotNull);
      expect(result!.stage, -2);
      expect(getCount, greaterThan(0));
    });
  });
}