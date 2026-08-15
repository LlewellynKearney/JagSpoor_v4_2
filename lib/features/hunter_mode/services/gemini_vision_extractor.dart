import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

import '../../../core/services/gemini_config_service.dart';
import 'pricelist_text_parser.dart';

/// Gemini Vision-backed extractor for South African hunting price lists.
///
/// Sends the scanned image / PDF bytes to Google's Gemini Vision model with a
/// structured JSON prompt that explicitly asks for species, sex/class, trophy
/// size range and ZAR price per line — and is primed with the Afrikaans
/// hunting vocabulary so the model returns Afrikaans terms it recognises.
/// The returned JSON is then routed through [GeminiResultNormalizer] /
/// [PricelistTextParser] so Afrikaans names map to the project's canonical
/// system species IDs while the original scanned label is preserved.
///
/// The API key is resolved through the centralized [GeminiConfigService]
/// three-tier fallback chain:
///  1. `--dart-define=GEMINI_API_KEY=...` (compile-time).
///  2. `Platform.environment['GEMINI_API_KEY']` (desktop / CI runtime env).
///  3. Local storage (SharedPreferences `jagspoor_gemini_api_key`) runtime
///     fallback when `--dart-define` was omitted at compile time.
/// When no key is configured from any source the extractor is considered
/// unavailable ([isAvailable] returns false) and callers should surface a
/// clear message instead of faking results.
class GeminiVisionExtractor {
  /// Optional explicit key (overrides the resolver, used by tests). When
  /// null the key is resolved from [GeminiConfigService].
  GeminiVisionExtractor({
    String? apiKey,
    String model = 'gemini-1.5-flash',
    GeminiConfigService? configService,
  })  : _explicitKey = apiKey,
        _model = model,
        _configService = configService;

  final String? _explicitKey;
  final String _model;
  final GeminiConfigService? _configService;

  /// The resolved API key: an explicit ctor key wins, otherwise the
  /// [GeminiConfigService] resolver (dart-define → env → local storage).
  String get _apiKey => _explicitKey ?? (_configService ?? GeminiConfigService.instance).apiKey;

  bool get isAvailable => _apiKey.isNotEmpty;

  static const String _afrikaansVocab = '''
South African hunting vocabulary you MUST recognise and preserve:
Species (Afrikaans -> English): Vlakvark=Warthog, Blesbok, Springbok, Rooibok=Impala,
Koedoe=Kudu, Blouwildebees=Blue Wildebeest, Swartwildebees=Black Wildebeest,
Gemsbok=Oryx, Eland, Bosbok=Bushbuck, Waterbok=Waterbuck, Rooihartbees=Red Hartebeest,
Nyala, Sebra=Zebra, Duiker, Steenbok, Takbok=Fallow Deer.
Sex/Class: Bul / Ram = Male/Trophy; Koei / Ooi / Ewe = Female; Jongbul / Penkop = Young Male; Knypkop = young male.
Fees: Dagfooi=Daily Rate; Slagfooi=Slaughter Fee; Gidskoste=Guide Fee; Wildrit=Game Drive; Bakkiefooi=Vehicle Fee.
''';

  static const String _instruction = '''
You are an OCR + structured-data extractor for South African hunting price lists.
Read the attached image/PDF and extract EVERY priced line item. Return ONLY a JSON
array (no markdown, no prose). Each element must be:
{"type":"species"|"fee","species":"<animal name as printed, Afrikaans or English>","sex":"<Bul/Ram/Koei/Ooi/Jongbul/Penkop/Knypkop/Male/Female or empty>","sizeRange":"<e.g. >50" or <20" or 40"-50" or empty>","priceZAR":<number, base price before commission>,"feeType":"<daily|slaughter|guide|gamedrive|vehicle|accommodation|meals|transport or empty>","quantityLimit":<integer max animals available/allowed for this line, or null when not stated>,"displayLabel":"<the full original line text as printed>"}
- priceZAR is a number in Rand (strip the R / ZAR / spaces / thousand separators).
- quantityLimit is the maximum number of animals available or allowed for that line (e.g. "x3", "max 5", "3 available", a "Qty" column). Use null when the price list does not state a limit.
- Preserve the original printed species + sex wording in "species"/"sex"/"displayLabel"; do NOT translate.
- For daily/slaughter/guide/game-drive/vehicle/accommodation/meals/transport lines use type "fee" and put the category in "feeType".
- If a line has no price, omit it.
Afrikaans vocabulary reference:
$_afrikaansVocab''';

  /// Extracts structured price-list items from [file] (image or PDF).
  /// Throws if the API key is missing or the call fails.
  Future<List<PricelistItem>> extract(File file) async {
    if (!isAvailable) {
      throw StateError(
        'Gemini Vision API key not configured. Set GEMINI_API_KEY to enable '
        'AI price-list extraction.',
      );
    }
    final bytes = await file.readAsBytes();
    final mimeType = _mimeTypeFor(file.path);
    final model = GenerativeModel(
      model: _model,
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0,
      ),
    );
    final content = [
      Content.text(_instruction),
      Content.data(mimeType, bytes),
    ];
    final response = await model.generateContent(content);
    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      return const <PricelistItem>[];
    }
    return parseGeminiTextResponse(text);
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Reads raw bytes for testing / reuse.
  Future<Uint8List> readBytes(File file) => file.readAsBytes();
}
