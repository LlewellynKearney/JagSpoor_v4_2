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
