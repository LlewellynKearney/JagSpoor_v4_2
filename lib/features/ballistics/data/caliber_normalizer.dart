/// Caliber Normalizer Service
/// Provides robust caliber string matching for Firestore queries
/// by generating comprehensive variant lists that bypass exact-match boundaries.
class CaliberNormalizer {
  /// Returns a curated list of caliber string variations for Firestore queries.
  /// Handles common naming conventions, regional variants, and commercial suffixes.
  static List<String> getVariants(String rawCaliber) {
    if (rawCaliber.isEmpty) return [''];

    final String clean = rawCaliber.trim().toLowerCase().replaceAll('.', '').replaceAll(' ', '');

    // .243 Winchester / 6mm variants
    if (clean == '243' || clean == '243win' || clean == '6mm' || clean == '6mmmusgrave') {
      return [
        '243 Win',
        '.243 Win',
        '243',
        '.243',
        '243 Winchester',
        '6mm Musgrave',
        '6mm',
        '6mm Rem',
      ];
    }

    // .308 Winchester variants
    if (clean == '308' || clean == '308win') {
      return [
        '308 Win',
        '.308 Win',
        '308',
        '.308',
        '308 Winchester',
        '.308 Win',
        '7.62mm NATO',
        '7.62 NATO',
      ];
    }

    // .30-06 Springfield variants
    if (clean == '3006' || clean == '30-06' || clean == '3006sprg' || clean == '3006springfield') {
      return [
        '30-06 Sprg',
        '30-06',
        '.30-06',
        '30-06 Springfield',
        '3006',
        '.30-06',
        '30-06',
      ];
    }

    // 6.5mm Creedmoor variants
    if (clean == '65' || clean == '65cm' || clean == '65creedmoor' || clean == '65creed') {
      return [
        '6.5 Creedmoor',
        '6.5CM',
        '6.5 Creed',
        '6.5',
        '.6.5 Creedmoor',
        '6.5mm Creedmoor',
      ];
    }

    // 7mm-08 Remington variants
    if (clean == '708' || clean == '708rem' || clean == '7mm08') {
      return [
        '7mm-08 Rem',
        '7mm-08',
        '7-08',
        '.7mm-08',
        '7mm 08',
      ];
    }

    // .270 Winchester variants
    if (clean == '270' || clean == '270win' || clean == '270winchester') {
      return [
        '270 Win',
        '270 Winchester',
        '270',
        '.270 Win',
        '.270',
      ];
    }

    // .223 Remington / 5.56 NATO variants
    if (clean == '223' || clean == '223rem' || clean == '223remington') {
      return [
        '223 Rem',
        '.223 Rem',
        '223',
        '.223',
        '223 Remington',
        '5.56 NATO',
        '5.56mm NATO',
        '.223',
      ];
    }

    // .22-250 Remington variants
    if (clean == '22250' || clean == '22250rem' || clean == '22250remington') {
      return [
        '22-250 Rem',
        '22-250',
        '.22-250',
        '22-250 Remington',
      ];
    }

    // .17 HMR variants
    if (clean == '17hmr' || clean == '17hrm' || clean == '17hmr') {
      return [
        '17 HMR',
        '.17 HMR',
        '17HMR',
        '.17HMR',
        '17 Win Mag',
      ];
    }

    // .300 Winchester Magnum variants
    if (clean == '300wm' || clean == '300winmag' || clean == '300winchestermag') {
      return [
        '300 Win Mag',
        '300 WM',
        '.300 Win Mag',
        '300 Winchester Magnum',
        '300 Win',
      ];
    }

    // .338 Lapua Magnum variants
    if (clean == '338lm' || clean == '338lapua' || clean == '338lapuamag') {
      return [
        '338 Lapua Mag',
        '338 LM',
        '.338 Lapua',
        '338 Lapua',
      ];
    }

    // .300 Blackout variants
    if (clean == '300blk' || clean == '300blackout' || clean == '7.62x35') {
      return [
        '300 Blackout',
        '300 BLK',
        '.300 Blackout',
        '7.62x35',
      ];
    }

    // .450 Bushmaster variants
    if (clean == '450bm' || clean == '450bushmaster' || clean == '45bm') {
      return [
        '450 Bushmaster',
        '450 BM',
        '.450 Bushmaster',
      ];
    }

    // Generic fallback with common variations
    // Strip leading dot and add variations
    final List<String> variants = [rawCaliber];

    if (rawCaliber.startsWith('.')) {
      variants.add(rawCaliber.substring(1));
    } else {
      variants.add('.$rawCaliber');
    }

    // Add common suffix variants
    if (!rawCaliber.toLowerCase().contains('win') && !rawCaliber.toLowerCase().contains('nato')) {
      variants.add('$rawCaliber Win');
      variants.add('$rawCaliber Winchester');
    }

    if (rawCaliber.contains('5.56') || rawCaliber.contains('556')) {
      variants.addAll(['5.56 NATO', '5.56mm NATO', '.223 Rem', '223 Rem']);
    }

    if (rawCaliber.contains('7.62') || rawCaliber.contains('762')) {
      variants.addAll(['7.62mm NATO', '7.62 NATO']);
    }

    return variants.toSet().toList();
  }

  /// Quick normalization for display purposes.
  /// Returns a clean, standardized caliber string.
  static String normalize(String rawCaliber) {
    if (rawCaliber.isEmpty) return '';

    String normalized = rawCaliber.trim();

    // Standardize common variants
    final lower = normalized.toLowerCase();
    if (lower.contains('308')) return '308 Win';
    if (lower.contains('243')) return '243 Win';
    if (lower.contains('3006') || lower.contains('30-06')) return '30-06';
    if (lower.contains('65creed') || lower.contains('6.5cm')) return '6.5 Creedmoor';
    if (lower.contains('223')) return '223 Rem';
    if (lower.contains('270')) return '270 Win';
    if (lower.contains('300blk') || lower.contains('300blackout')) return '300 Blackout';

    return normalized;
  }
}
