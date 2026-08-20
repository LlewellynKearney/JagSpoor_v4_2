import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/photo_unavailable_placeholder.dart';
import '../../../utils/image_helper.dart';
import '../services/photo_gallery_resolver.dart';

/// Normalized farm snapshot for hunter-facing surfaces (Custom Package
/// Builder, Trophy Registry confirmation sheet).
///
/// A `farms/{farmId}` document stores its identity under a mixture of fields
/// written across the app's phases (`name`, `farmName`; `district`, `town`;
/// `photoUrl`, `photoUrls`, `imageUrls`). [FarmDetails.fromMap] resolves all
/// of them into one immutable value object so screens never need to know
/// which alias the outfitter's registration form wrote.
class FarmDetails {
  final String farmId;
  final String outfitterId;
  final String? name;
  final String? district;
  final String? province;
  final String? town;
  final String? contactNumber;
  final String? registrationNumber;
  final double? sizeHectares;
  final List<String> photoUrls;

  const FarmDetails({
    this.farmId = '',
    this.outfitterId = '',
    this.name,
    this.district,
    this.province,
    this.town,
    this.contactNumber,
    this.registrationNumber,
    this.sizeHectares,
    this.photoUrls = const [],
  });

  static String _clean(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? '' : s;
  }

  /// Hydrates from a raw `farms` document map (or any map carrying the same
  /// fields). Tolerates `name`/`farmName`, `town`/`district`, and every
  /// photo-field alias via [resolveGalleryUrls].
  factory FarmDetails.fromMap(Map<String, dynamic>? data) {
    final d = data ?? const <String, dynamic>{};
    final name = _clean(d['name']).isNotEmpty
        ? _clean(d['name'])
        : _clean(d['farmName']);
    final town = _clean(d['town']).isNotEmpty
        ? _clean(d['town'])
        : _clean(d['district']);
    return FarmDetails(
      farmId: _clean(d['farmId']),
      outfitterId: _clean(d['outfitterId']),
      name: name.isEmpty ? null : name,
      district: _clean(d['district']).isEmpty ? null : _clean(d['district']),
      province:
          _clean(d['province']).isEmpty ? null : _clean(d['province']),
      town: town.isEmpty ? null : town,
      contactNumber: _clean(d['contactNumber']).isEmpty
          ? null
          : _clean(d['contactNumber']),
      registrationNumber: _clean(d['registrationNumber']).isEmpty
          ? null
          : _clean(d['registrationNumber']),
      sizeHectares: (d['sizeHectares'] as num?)?.toDouble(),
      photoUrls: resolveGalleryUrls(d),
    );
  }

  /// Display name with the standard fallback.
  String get displayName => (name != null && name!.isNotEmpty)
      ? name!
      : (farmId.isEmpty ? 'Unnamed Farm' : 'Farm');

  /// The farm's primary photo (first URL), or null when it has none.
  String? get primaryPhotoUrl =>
      photoUrls.isEmpty ? null : photoUrls.first;

  /// Location summary chips -- (icon, label) data pairs for every non-empty
  /// farm detail the screen can surface. Labels that depend on a value
  /// ("Contact: ...") are skipped when the value is absent.
  List<(IconData, String)> get infoChips {
    final chips = <(IconData, String)>[];
    void add(IconData icon, String? value, [String prefix = '']) {
      final v = value?.trim() ?? '';
      if (v.isEmpty) return;
      chips.add((icon, '$prefix$v'));
    }

    add(Icons.map_outlined, province);
    add(Icons.location_on_outlined, district);
    add(Icons.location_city_outlined, town);
    add(Icons.landscape_outlined, sizeHectares != null
        ? '${sizeHectares!.toStringAsFixed(0)} ha'
        : null);
    add(Icons.phone_outlined, contactNumber);
    add(Icons.badge_outlined, registrationNumber);
    return chips;
  }
}

/// Rounded farm thumbnail used by hunter-facing farm cards / panels: the
/// farm's uploaded photo via the resilient [AdaptiveImage] pipeline, or a
/// clean placeholder icon when the farm has no photo.
class FarmThumbnail extends StatelessWidget {
  /// The resolved photo URL (blank/absent -> placeholder).
  final String? photoUrl;
  final ThemeController theme;
  final double size;
  final double radius;

  const FarmThumbnail({
    super.key,
    required this.photoUrl,
    required this.theme,
    this.size = 60,
    this.radius = 10,
  });

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.terrain_rounded,
        color: theme.accentColor,
        size: size * 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim() ?? '';
    if (url.isEmpty) return _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: AdaptiveImage(
          imagePath: url,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorWidget: const PhotoUnavailablePlaceholder(
            icon: Icons.terrain_rounded,
            label: 'No photo',
          ),
        ),
      ),
    );
  }
}
