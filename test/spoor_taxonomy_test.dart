import 'package:flutter_test/flutter_test.dart';
import 'package:jagspoor/features/track/data/track_taxonomy.dart';

void main() {
  test('Leopard is paw/carnivore, Kudu is ungulate, Zebra is equine', () {
    expect(categoryForSpecies('Leopard'), TrackCategory.pawCarnivore);
    expect(categoryForSpecies('Kudu'), TrackCategory.clovenHoofUngulate);
    expect(categoryForSpecies('Zebra'), TrackCategory.solidHoofEquine);
    expect(categoryForSpecies('Cheetah'), TrackCategory.pawCarnivore);
    expect(categoryForSpecies('Impala'), TrackCategory.clovenHoofUngulate);
    expect(categoryForSpecies('Donkey'), TrackCategory.solidHoofEquine);
  });

  test('categoryLabel/hint/prompts cover all categories', () {
    for (final c in TrackCategory.values) {
      expect(categoryLabel(c).isNotEmpty, true);
      expect(categoryHint(c).isNotEmpty, true);
      expect(verificationPrompts(c).length, 3);
    }
  });

  test('a Leopard (paw) is NEVER classified as a Kudu (ungulate) when filtered',
      () {
    const leopardCat = TrackCategory.pawCarnivore;
    expect(categoryForSpecies('Kudu') == leopardCat, isFalse);
    expect(categoryForSpecies('Impala') == leopardCat, isFalse);
    expect(categoryForSpecies('Gemsbok') == leopardCat, isFalse);
    expect(categoryForSpecies('Leopard') == leopardCat, isTrue);
  });

  test('unknown species defaults to ungulate', () {
    expect(categoryForSpecies('Mystery Animal'), TrackCategory.clovenHoofUngulate);
  });

  test('SpoorPrediction confidencePercent helper', () {
    const p = SpoorPrediction(species: 'Leopard', confidence: 0.88);
    expect(p.confidencePercent, closeTo(88.0, 0.001));
  });
}
