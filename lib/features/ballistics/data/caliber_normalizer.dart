/// Caliber Normalizer Service
/// Provides robust caliber string matching for Firestore queries
/// by generating comprehensive variant lists that bypass exact-match boundaries.
///
/// Formats verified against: assets/data/ammunition_database.csv
class CaliberNormalizer {
  /// Returns a curated list of caliber string variations for Firestore queries.
  /// Handles common naming conventions, regional variants, and commercial suffixes.
  /// 
  /// All variants are cross-referenced against ammunition_database.csv formats.
  static List<String> getVariants(String rawCaliber) {
    if (rawCaliber.isEmpty) return [''];

    final String clean = rawCaliber.trim().toLowerCase().replaceAll('.', '').replaceAll(' ', '').replaceAll('-', '');

    // .243 Winchester variants (verified from DB: ".243 Win")
    if (clean == '243' || clean == '243win') {
      return [
        '.243 Win',
        '243 Win',
        '243',
        '6mm',
        '6mm Rem',
      ];
    }

    // .308 Winchester variants (verified from DB: ".308 Win")
    if (clean == '308' || clean == '308win') {
      return [
        '.308 Win',
        '308 Win',
        '308',
        '.308 Cal',
        '308 Cal',
        '7.62mm NATO',
        '7.62 NATO',
        '7.62x51mm',
      ];
    }

    // .30-06 Springfield variants (verified from DB: ".30-06 Sprg")
    if (clean == '3006' || clean == '3006sprg' || clean == '30-06') {
      return [
        '.30-06 Sprg',
        '30-06 Sprg',
        '30-06',
        '.30-06',
        '30-06 Springfield',
        '3006',
      ];
    }

    // 6.5mm Creedmoor variants (verified from DB: "6.5 Creedmoor")
    if (clean == '65' || clean == '65creedmoor' || clean == '65cm') {
      return [
        '6.5 Creedmoor',
        '6.5mm Creedmoor',
        '6.5',
        '6.5mm',
      ];
    }

    // 7mm-08 Remington variants (verified from DB: "7mm-08 Rem")
    if (clean == '708' || clean == '7mm08' || clean == '708rem') {
      return [
        '7mm-08 Rem',
        '7mm-08',
        '7-08',
        '7mm 08',
      ];
    }

    // .270 Winchester variants (verified from DB: ".270 Win", ".270 Cal")
    if (clean == '270' || clean == '270win' || clean == '270winchester') {
      return [
        '.270 Win',
        '270 Win',
        '270',
        '.270 Cal',
        '270 Cal',
      ];
    }

    // .223 Remington variants (verified from DB: ".223 Rem")
    if (clean == '223' || clean == '223rem' || clean == '223remington') {
      return [
        '.223 Rem',
        '223 Rem',
        '223',
        '5.56 NATO',
        '5.56mm NATO',
        '5.56x45mm',
      ];
    }

    // .22-250 Remington variants (verified from DB: ".22-250 Rem")
    if (clean == '22250' || clean == '22250rem' || clean == '22250remington') {
      return [
        '.22-250 Rem',
        '22-250 Rem',
        '22-250',
      ];
    }

    // .22 WMR variants (verified from DB: ".22 WMR")
    if (clean == '22wmr' || clean == '22wmr') {
      return [
        '.22 WMR',
        '22 WMR',
        '22 WMR',
      ];
    }

    // .22 Hornet variants (verified from DB: ".22 Hornet")
    if (clean == '22hornets' || clean == '22hornet') {
      return [
        '.22 Hornet',
        '22 Hornet',
        '22 Hornet',
      ];
    }

    // .300 Winchester Magnum variants (verified from DB: ".300 Win Mag")
    if (clean == '300wm' || clean == '300winmag' || clean == '300winchestermag') {
      return [
        '.300 Win Mag',
        '300 Win Mag',
        '300 WM',
        '300 Winchester Magnum',
      ];
    }

    // .300 WSM variants (verified from DB: ".300 WSM")
    if (clean == '300wsm' || clean == '300wsm') {
      return [
        '.300 WSM',
        '300 WSM',
        '300 Win Short Mag',
      ];
    }

    // .300 Blackout variants (verified from DB: ".300 Blackout", ".300 AAC Blackout")
    if (clean == '300blk' || clean == '300blackout' || clean == '7.62x35') {
      return [
        '.300 Blackout',
        '300 Blackout',
        '.300 AAC Blackout',
        '300 AAC Blackout',
        '7.62x35',
      ];
    }

    // .300 PRC variants (verified from DB: ".300 PRC")
    if (clean == '300prc' || clean == '300prc') {
      return [
        '.300 PRC',
        '300 PRC',
      ];
    }

    // 6.5 PRC variants (verified from DB: "6.5 PRC")
    if (clean == '65prc' || clean == '65prc') {
      return [
        '6.5 PRC',
        '6.5mm PRC',
      ];
    }

    // .338 Winchester Magnum variants (verified from DB: ".338 Win Mag")
    if (clean == '338wm' || clean == '338winmag' || clean == '338winchestermag') {
      return [
        '.338 Win Mag',
        '338 Win Mag',
        '338 WM',
      ];
    }

    // .375 H&H Magnum variants (verified from DB: ".375 H&H Mag", ".375 H&H")
    if (clean == '375hh' || clean == '375h&hmag' || clean == '375hheh') {
      return [
        '.375 H&H Mag',
        '375 H&H Mag',
        '.375 H&H',
        '375 H&H',
      ];
    }

    // 7mm Remington Magnum variants (verified from DB: "7mm Rem Mag")
    if (clean == '7mmremmag' || clean == '7mmremmag') {
      return [
        '7mm Rem Mag',
        '7mm Remington Magnum',
      ];
    }

    // 6.5x55 SE variants (verified from DB: "6.5x55 SE")
    if (clean == '65x55' || clean == '65x55se') {
      return [
        '6.5x55 SE',
        '6.5x55 Swedish',
        '6.5x55',
      ];
    }

    // 7x57 / 7x64 variants (verified from DB: "7x57", "7x64")
    if (clean == '7x57' || clean == '7x64') {
      return [
        '7x57',
        '7x64',
        '7x57mm',
        '7x64mm',
        '7mm Mauser',
      ];
    }

    // .22 LR variants (verified from DB: ".22 LR")
    if (clean == '22lr' || clean == '22lr') {
      return [
        '.22 LR',
        '22 LR',
        '22 LR',
      ];
    }

    // .303 British variants (verified from DB: ".303 British")
    if (clean == '303british' || clean == '303british') {
      return [
        '.303 British',
        '303 British',
        '7.7mm Arisaka',
      ];
    }

    // .30-30 Winchester variants (verified from DB: ".30-30 Win")
    if (clean == '30-30' || clean == '3030win' || clean == '3030') {
      return [
        '.30-30 Win',
        '30-30 Win',
        '.30-30',
        '30-30',
      ];
    }

    // .450 Bushmaster variants
    if (clean == '450bm' || clean == '450bushmaster') {
      return [
        '.450 Bushmaster',
        '450 Bushmaster',
        '450 BM',
      ];
    }

    // .38 Special / .357 Magnum variants
    if (clean == '38special' || clean == '357mag' || clean == '357magnum') {
      return [
        '.38 Special',
        '38 Special',
        '.357 Mag',
        '357 Mag',
        '.357 Magnum',
        '357 Magnum',
      ];
    }

    // .40 S&W variants
    if (clean == '40sw' || clean == '40s&w') {
      return [
        '.40 S&W',
        '40 S&W',
        '.40',
        '40',
      ];
    }

    // .44 Magnum variants
    if (clean == '44mag' || clean == '44remmag') {
      return [
        '.44 Mag',
        '44 Mag',
        '.44 Rem Mag',
        '44 Rem Mag',
      ];
    }

    // .45 ACP / .45 Auto variants
    if (clean == '45acp' || clean == '45auto') {
      return [
        '.45 Auto',
        '45 Auto',
        '.45 ACP',
        '45 ACP',
      ];
    }

    // .45-70 Government variants
    if (clean == '45-70' || clean == '4570govt' || clean == '4570') {
      return [
        '.45-70 Govt',
        '45-70 Govt',
        '.45-70 Government',
        '45-70 Government',
      ];
    }

    // .380 Auto variants
    if (clean == '380auto' || clean == '380') {
      return [
        '.380 Auto',
        '380 Auto',
        '.380',
        '380',
      ];
    }

    // .32 ACP variants
    if (clean == '32acp' || clean == '32auto') {
      return [
        '.32 ACP',
        '32 ACP',
        '.32 Auto',
        '32 Auto',
      ];
    }

    // 9mm variants (verified from DB: "9mm Luger", "9mm", "9mm +P")
    if (clean == '9mm' || clean == '9mmluger' || clean == '9nato') {
      return [
        '9mm Luger',
        '9mm',
        '9mm +P',
        '9mm Luger +P',
        '9x19mm',
        '9x19mm Parabellum',
      ];
    }

    // 7.62x39mm variants (verified from DB: "7.62x39mm", "7.62x39")
    if (clean == '7.62x39' || clean == '762x39' || clean == '7.62x39mm') {
      return [
        '7.62x39mm',
        '7.62x39',
        '.762x39',
        '7.62 Soviet',
      ];
    }

    // 10mm Auto variants
    if (clean == '10mmauto' || clean == '10mm') {
      return [
        '10mm Auto',
        '10mm',
        '.40 S&W',
      ];
    }

    // .25 Auto variants
    if (clean == '25auto' || clean == '25acp') {
      return [
        '.25 Auto',
        '25 Auto',
        '.25 ACP',
        '25 ACP',
      ];
    }

    // .30 Carbine variants
    if (clean == '30carbine' || clean == '30car') {
      return [
        '.30 Carbine',
        '30 Carbine',
        '7.62x33mm',
      ];
    }

    // .470 Nitro Express variants
    if (clean == '470nitro' || clean == '470ne') {
      return [
        '.470 Nitro Express',
        '470 Nitro Express',
      ];
    }

    // .404 Jeffery variants
    if (clean == '404jeffery' || clean == '404j') {
      return [
        '.404 Jeffery',
        '404 Jeffery',
      ];
    }

    // .222 Rem variants
    if (clean == '222rem' || clean == '222remington') {
      return [
        '.222 Rem',
        '222 Rem',
        '.222 Remington',
        '222 Remington',
      ];
    }

    // .25-06 Rem variants
    if (clean == '2506' || clean == '2506rem') {
      return [
        '.25-06 Rem',
        '25-06 Rem',
        '25-06',
      ];
    }

    // .338 Lapua Magnum variants
    if (clean == '338lm' || clean == '338lapua') {
      return [
        '.338 Lapua Mag',
        '338 Lapua Mag',
        '338 LM',
      ];
    }

    // 12 Gauge / .410 Gauge variants
    if (clean == '12gauge' || clean == '12g') {
      return [
        '12 Gauge',
        '12 Gauge',
      ];
    }

    if (clean == '410gauge' || clean == '410g') {
      return [
        '.410 Gauge',
        '410 Gauge',
      ];
    }

    // Generic fallback with common variations
    final List<String> variants = [rawCaliber];

    // Strip leading dot
    if (rawCaliber.startsWith('.')) {
      variants.add(rawCaliber.substring(1));
    } else {
      variants.add('.$rawCaliber');
    }

    // Add common suffix variants for Winchester pattern
    final lowerCaliber = rawCaliber.toLowerCase();
    if (!lowerCaliber.contains('win') && 
        !lowerCaliber.contains('nato') && 
        !lowerCaliber.contains('mag') &&
        !lowerCaliber.contains('prc')) {
      variants.add('$rawCaliber Win');
      variants.add('$rawCaliber Winchester');
    }

    return variants.toSet().toList();
  }

  /// Quick normalization for display purposes.
  /// Returns a clean, standardized caliber string.
  static String normalize(String rawCaliber) {
    if (rawCaliber.isEmpty) return '';

    String normalized = rawCaliber.trim();
    final lower = normalized.toLowerCase().replaceAll(' ', '');

    if (lower.contains('308')) return '.308 Win';
    if (lower.contains('243')) return '.243 Win';
    if (lower.contains('3006') || lower.contains('30-06')) return '.30-06 Sprg';
    if (lower.contains('65creed')) return '6.5 Creedmoor';
    if (lower.contains('223')) return '.223 Rem';
    if (lower.contains('270') && !lower.contains('270win')) return '.270 Win';
    if (lower.contains('270win')) return '.270 Win';
    if (lower.contains('300blk') || lower.contains('300blackout')) return '.300 Blackout';
    if (lower.contains('300winmag')) return '.300 Win Mag';
    if (lower.contains('9mm')) return '9mm Luger';
    if (lower.contains('7.62x39')) return '7.62x39mm';

    return normalized;
  }
}
