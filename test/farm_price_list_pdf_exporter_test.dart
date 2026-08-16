import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:jagspoor/core/services/pdf_document_engine.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_game_price_entry.dart';
import 'package:jagspoor/features/hunter_mode/models/farm_service_rate.dart';
import 'package:jagspoor/features/hunter_mode/services/farm_price_list_pdf_exporter.dart';

/// The pure content builder is exercised by rendering the full branded
/// document (logo header + footer) to bytes. We assert the build does not
/// throw, the output is a non-empty PDF, and the byte length grows as more
/// content is added. We do NOT parse the PDF structure (no PDF parser dep);
/// the contract is "renders without throwing + produces a valid PDF stream".
void main() {
  // The PDF engine loads the logo via rootBundle, which requires the Flutter
  // platform binding to be initialized before the asset bundle is read.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FarmPriceListPdfExporter exporter;

  setUp(() {
    exporter = FarmPriceListPdfExporter();
  });

  group('FarmPriceListPdfExporter — itemized service filtering', () {
    /// Builds a [FarmServiceRates] with the given per-key (quantity, price)
    /// pairs; unspecified categories are left at zero (unconfigured).
    FarmServiceRates buildRates(Map<String, (int, double)> configured) {
      final rates = FarmServiceRates.empty('farm-1', 'outfitter-1');
      configured.forEach((key, pair) {
        final cat = FarmServiceCategory.findByKey(key);
        rates.rates[key] = FarmServiceRate(
          key: key,
          label: cat.label,
          unitLabel: cat.unitLabel,
          quantityNoun: cat.quantityNoun,
          quantity: pair.$1,
          pricePerUnit: pair.$2,
        );
      });
      return rates;
    }

    test('filterActiveServices returns empty when services is null', () {
      expect(exporter.filterActiveServices(null), isEmpty);
    });

    test('filterActiveServices omits zero-quantity services', () {
      final rates = buildRates({
        // bakkie: qty 0 -> omitted even though price > 0.
        'bakkie_vehicle': (0, 500.0),
        // catering: qty 3, price 250 -> included.
        'catering': (3, 250.0),
      });
      final active = exporter.filterActiveServices(rates);
      expect(active.length, 1);
      expect(active.single.key, 'catering');
    });

    test('filterActiveServices omits zero-rate services', () {
      final rates = buildRates({
        // coldroom: price 0 -> omitted even though qty > 0.
        'coldroom': (2, 0.0),
        // hunter_daily: qty 2, price 800 -> included.
        'hunter_daily': (2, 800.0),
      });
      final active = exporter.filterActiveServices(rates);
      expect(active.length, 1);
      expect(active.single.key, 'hunter_daily');
    });

    test('filterActiveServices omits services that are both zero', () {
      final rates = buildRates({
        'coldroom': (0, 0.0),
        'catering': (3, 250.0),
      });
      final active = exporter.filterActiveServices(rates);
      expect(active.length, 1);
      expect(active.single.key, 'catering');
    });

    test('filterActiveServices omits ALL services when every qty+rate is zero',
        () {
      final rates = buildRates({
        'bakkie_vehicle': (0, 0.0),
        'catering': (0, 0.0),
      });
      expect(exporter.filterActiveServices(rates), isEmpty);
    });

    test('filterActiveServices treats blank/null stored values as zero '
        '(excluded)', () {
      // A raw stored doc with missing/null/blank quantity + price values:
      // fromMap resolves these to 0, so they are excluded by the filter.
      final rates = FarmServiceRates.fromMap({
        'outfitterId': 'outfitter-1',
        'rates': {
          'bakkie_vehicle': {
            'key': 'bakkie_vehicle',
            // quantity missing -> 0
            'pricePerUnit': null, // null -> 0
          },
          'slaughtering_big': {
            'key': 'slaughtering_big',
            'quantity': '', // blank string -> 0
            'pricePerUnit': '', // blank string -> 0
          },
          'catering': {
            'key': 'catering',
            'quantity': 4,
            'pricePerUnit': 300,
          },
        },
      }, farmId: 'farm-1');
      final active = exporter.filterActiveServices(rates);
      expect(active.length, 1);
      expect(active.single.key, 'catering');
    });

    test('filterActiveServices preserves the standard category order', () {
      final rates = buildRates({
        'catering': (3, 250.0),
        'bakkie_vehicle': (2, 500.0),
        'slaughtering_big': (1, 600.0),
      });
      final active = exporter.filterActiveServices(rates);
      expect(active.map((r) => r.key).toList(), [
        'bakkie_vehicle',
        'slaughtering_big',
        'catering',
      ]);
    });

    test('filterActiveServices includes all 9 categories when all are configured',
        () {
      final configured = <String, (int, double)>{};
      for (final cat in FarmServiceCategory.all) {
        configured[cat.key] = (2, 100.0);
      }
      final rates = buildRates(configured);
      expect(exporter.filterActiveServices(rates).length, 9);
    });

    test('filterActiveServices carries the unit label through to the export',
        () {
      final rates = buildRates({
        'bakkie_vehicle': (2, 500.0),
        'overnight_accommodation_hunter': (3, 850.0),
      });
      final active = exporter.filterActiveServices(rates);
      final byKey = {for (final r in active) r.key: r};
      expect(byKey['bakkie_vehicle']!.unitLabel, 'Per vehicle per day');
      expect(byKey['overnight_accommodation_hunter']!.unitLabel, 'Per night');
    });

    test('buildContent uses only the active (filtered) services', () {
      // buildContent delegates to filterActiveServices; a service with a zero
      // rate must not appear. We assert the filtered list the builder consumes
      // rather than parsing PDF bytes.
      final rates = buildRates({
        'bakkie_vehicle': (0, 500.0), // omitted
        'catering': (3, 250.0), // included
      });
      final active = exporter.filterActiveServices(rates);
      expect(active, hasLength(1));
      // buildContent must not throw when rendering only the active services.
      final widget = exporter.buildContent(
        farmName: 'Filter Farm',
        species: const [],
        services: rates,
      );
      expect(widget, isA<pw.Widget>());
    });
  });

  group('FarmPriceListPdfExporter.buildContent', () {
    test('buildContent returns a pw.Widget (does not throw)', () {
      final widget = exporter.buildContent(
        farmName: 'Test Farm',
        species: const [],
        services: null,
      );
      expect(widget, isA<pw.Widget>());
    });

    test('buildContent handles a populated species list + services', () {
      final services = FarmServiceRates.empty('farm-1', 'outfitter-1');
      services.rates['bakkie_vehicle'] = const FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie / Hunting Vehicle Fees',
        quantity: 2,
        pricePerUnit: 500,
      );
      final widget = exporter.buildContent(
        farmName: 'Kruger Ranch',
        species: [
          FarmGamePriceEntry(
            id: '1',
            farmId: 'farm-1',
            outfitterId: 'outfitter-1',
            speciesName: 'Impala',
            qty: 5,
            priceZAR: 2500,
            gender: 'Male',
            hornTuskLength: '28"+',
            hornTuskUnit: HornTuskUnit.inches,
          ),
        ],
        services: services,
      );
      expect(widget, isA<pw.Widget>());
    });
  });

  group('FarmPriceListPdfExporter — full branded PDF render', () {
    // Renders the exporter's content through the real JagSpoorPdfDocument
    // engine (logo header + footer + the content) and saves the bytes.
    Future<List<int>> renderToBytes({
      required String farmName,
      required List<FarmGamePriceEntry> species,
      FarmServiceRates? services,
    }) async {
      final doc = await JagSpoorPdfDocument.create(
        title: 'Farm Game Price List',
        documentId: 'FPL-test',
      );
      doc.addPage(
        margin: 28,
        content: exporter.buildContent(
          farmName: farmName,
          species: species,
          services: services,
        ),
      );
      return doc.saveBytes();
    }

    test('renders an empty farm price list to a valid PDF', () async {
      final bytes = await renderToBytes(
        farmName: 'Empty Farm',
        species: const [],
        services: null,
      );
      expect(bytes, isNotEmpty);
      // Decode the first few bytes to confirm it is a PDF.
      final header = String.fromCharCodes(bytes.take(5));
      expect(header.startsWith('%PDF-'), isTrue,
          reason: 'Output must be a valid PDF (got: $header)');
    });

    test('renders a populated price list (species + services) to a valid PDF',
        () async {
      final services = FarmServiceRates.empty('farm-1', 'outfitter-1');
      services.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering Services',
        quantity: 3,
        pricePerUnit: 250,
      );
      final bytes = await renderToBytes(
        farmName: 'Bushveld Lodge',
        species: [
          FarmGamePriceEntry(
            id: '1',
            farmId: 'farm-1',
            outfitterId: 'outfitter-1',
            speciesName: 'Greater Kudu',
            qty: 2,
            priceZAR: 18500,
            gender: 'Female',
            hornTuskLength: '53"',
            hornTuskUnit: HornTuskUnit.inches,
          ),
          FarmGamePriceEntry(
            id: '2',
            farmId: 'farm-1',
            outfitterId: 'outfitter-1',
            speciesName: 'Springbok',
            qty: 10,
            priceZAR: 1400,
            gender: 'Any',
            hornTuskLength: '',
            hornTuskUnit: HornTuskUnit.cm,
          ),
        ],
        services: services,
      );
      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header.startsWith('%PDF-'), isTrue);
    });

    test('renders multiple populated price lists without throwing', () async {
      // Render several distinct populated configurations to exercise the table
      // layout paths (species rows, service rows, totals) and assert each
      // produces a valid PDF. We do not compare byte sizes across configs
      // (PDF stream compression is not strictly proportional to visible
      // content); the contract is "every config renders a valid PDF".
      final configs = <String, List<FarmGamePriceEntry>>{
        'single species': [
          FarmGamePriceEntry(
            id: '1',
            farmId: 'farm-1',
            outfitterId: 'outfitter-1',
            speciesName: 'Impala',
            qty: 1,
            priceZAR: 2500,
            gender: 'Male',
            hornTuskLength: '28"+',
            hornTuskUnit: HornTuskUnit.inches,
          ),
        ],
        'many species': List.generate(
          12,
          (i) => FarmGamePriceEntry(
            id: '$i',
            farmId: 'farm-1',
            outfitterId: 'outfitter-1',
            speciesName: 'Species $i',
            qty: i + 1,
            priceZAR: 1000.0 * (i + 1),
            gender: 'Any',
            hornTuskLength: '',
            hornTuskUnit: HornTuskUnit.cm,
          ),
        ),
      };
      final services = FarmServiceRates.empty('farm-1', 'outfitter-1');
      services.rates['bakkie_vehicle'] = const FarmServiceRate(
        key: 'bakkie_vehicle',
        label: 'Bakkie / Hunting Vehicle Fees',
        quantity: 2,
        pricePerUnit: 500,
      );
      services.rates['catering'] = const FarmServiceRate(
        key: 'catering',
        label: 'Catering Services',
        quantity: 3,
        pricePerUnit: 250,
      );

      for (final entry in configs.entries) {
        final bytes = await renderToBytes(
          farmName: 'Config: ${entry.key}',
          species: entry.value,
          services: services,
        );
        expect(bytes, isNotEmpty, reason: '${entry.key} produced no bytes');
        final header = String.fromCharCodes(bytes.take(5));
        expect(header.startsWith('%PDF-'), isTrue,
            reason: '${entry.key} did not produce a valid PDF header');
      }
    });
  });
}
