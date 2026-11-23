import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_camp_detail_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';
import 'package:latlong2/latlong.dart';

/// Geographic bounds of the camps that carry a location.
class VeldCampMapBounds {
  const VeldCampMapBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  bool get hasLatSpread => (maxLat - minLat).abs() > 1e-9;
  bool get hasLngSpread => (maxLng - minLng).abs() > 1e-9;

  double get centreLat => (minLat + maxLat) / 2;
  double get centreLng => (minLng + maxLng) / 2;

  /// Largest span in degrees, used to pick an initial zoom.
  double get maxSpan {
    final latSpan = (maxLat - minLat).abs();
    final lngSpan = (maxLng - minLng).abs();
    return latSpan > lngSpan ? latSpan : lngSpan;
  }
}

/// Pure layout maths for the camp map.
///
/// Kept free of Flutter / Firestore so the projection contract (which corner a
/// camp lands in) is unit-testable without a map widget or a network.
class VeldCampMapLayout {
  const VeldCampMapLayout._();

  /// Camps that carry both a latitude and a longitude.
  static List<Camp> campsWithLocation(Iterable<Camp> camps) =>
      camps.where((camp) => camp.lat != null && camp.lng != null).toList(
            growable: false,
          );

  /// Camps that are missing a latitude or a longitude.
  static List<Camp> campsWithoutLocation(Iterable<Camp> camps) =>
      camps.where((camp) => camp.lat == null || camp.lng == null).toList(
            growable: false,
          );

  /// Bounds of [camps], or null when none of them carries a location.
  static VeldCampMapBounds? boundsOf(Iterable<Camp> camps) {
    final located = campsWithLocation(camps);
    if (located.isEmpty) return null;
    var minLat = located.first.lat!;
    var maxLat = minLat;
    var minLng = located.first.lng!;
    var maxLng = minLng;
    for (final camp in located) {
      final lat = camp.lat!;
      final lng = camp.lng!;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    return VeldCampMapBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
    );
  }

  /// Normalised position of [camp] inside [bounds], both axes `0..1`.
  ///
  /// `x` grows west -> east with longitude; `y` grows north -> south so the
  /// result can be plotted directly on a screen (whose origin is top-left).
  /// A single camp (or camps on one axis) collapses to the centre of that
  /// axis instead of dividing by zero.
  static ({double x, double y}) relativePosition(
    Camp camp,
    VeldCampMapBounds bounds,
  ) {
    final lng = camp.lng;
    final lat = camp.lat;
    final x = (lng == null || !bounds.hasLngSpread)
        ? 0.5
        : (lng - bounds.minLng) / (bounds.maxLng - bounds.minLng);
    final y = (lat == null || !bounds.hasLatSpread)
        ? 0.5
        : 1 - (lat - bounds.minLat) / (bounds.maxLat - bounds.minLat);
    return (x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0));
  }

  /// A conservative initial zoom for [bounds] (4 = wide, 14 = tight).
  static double zoomFor(VeldCampMapBounds bounds) {
    final span = bounds.maxSpan;
    if (span <= 0) return 14;
    if (span < 0.01) return 13;
    if (span < 0.05) return 11;
    if (span < 0.2) return 9;
    if (span < 1) return 7;
    if (span < 5) return 5;
    return 4;
  }
}

/// Outfitter-only map of a farm's veld camps.
///
/// **Never shown to a hunter.** Every read goes through the ownership-gated
/// [VeldCarryRepository.getCamps] (`requireOwnership`), and the coordinates
/// this screen plots are never handed to a hunter screen, widget or repository
/// method.
///
/// Reached only from the flag-gated "Map" action on
/// [VeldCarryCampListScreen], so with the feature flag OFF this screen cannot
/// be opened at all.
class VeldCarryCampMapScreen extends StatefulWidget {
  const VeldCarryCampMapScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so the screen can be driven against a
  /// fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryCampMapScreen> createState() => _VeldCarryCampMapScreenState();
}

class _VeldCarryCampMapScreenState extends State<VeldCarryCampMapScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<Camp> _camps = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view the camp map.';
      });
      return;
    }
    try {
      // Owner-only read: `getCamps` calls `requireOwnership`, so this screen
      // can never plot another outfitter's camps.
      final camps = await _repository.getCamps(uid, widget.farmId);
      if (!mounted) return;
      setState(() {
        _camps = camps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the camp map: $e';
      });
    }
  }

  Future<void> _openCamp(Camp camp) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryCampDetailScreen(
          camp: camp,
          farmId: widget.farmId,
          farmName: widget.farmName,
          theme: _theme,
          repository: _repository,
        ),
      ),
    );
    // The detail screen can set or move a camp's location — re-read on return.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Camp Map',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (widget.farmName != null && widget.farmName!.isNotEmpty)
              Text(
                widget.farmName!,
                style: TextStyle(
                  color: OutfitterUi.subtitleColor(theme),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          OutfitterActionChip(
            key: const ValueKey('veldCampMapRefreshButton'),
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh map',
            iconColor: theme.accentColor,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeController theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }
    if (_error != null) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          _messageCard(theme, 'Could not load the camp map', _error!),
          const CopyrightFooter(),
        ],
      );
    }

    final located = VeldCampMapLayout.campsWithLocation(_camps);
    final unlocated = VeldCampMapLayout.campsWithoutLocation(_camps);
    final bounds = VeldCampMapLayout.boundsOf(_camps);

    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        _privacyNote(theme),
        const SizedBox(height: 12),
        if (located.isEmpty)
          _messageCard(
            theme,
            'No camps have location set yet',
            'Open a camp below and set its location to plot it on the map.',
          )
        else ...[
          _mapCard(theme, located, bounds!),
          const SizedBox(height: 12),
          _layoutCard(theme, located, bounds),
        ],
        if (unlocated.isNotEmpty) ...[
          const SizedBox(height: 12),
          _unlocatedCard(theme, unlocated),
        ],
        const SizedBox(height: 12),
        const CopyrightFooter(),
      ],
    );
  }

  /// The real geographic view — reuses the app's existing `flutter_map`
  /// dependency (the same one the off-grid navigation screen uses), so no new
  /// map SDK is introduced.
  Widget _mapCard(
    ThemeController theme,
    List<Camp> located,
    VeldCampMapBounds bounds,
  ) {
    return Container(
      key: const ValueKey('veldCampMap'),
      decoration: OutfitterUi.cardDecoration(theme),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 300,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(bounds.centreLat, bounds.centreLng),
            initialZoom: VeldCampMapLayout.zoomFor(bounds),
            minZoom: 3,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'za.co.jagspoor.app',
              maxZoom: 18,
            ),
            MarkerLayer(
              markers: [
                for (final camp in located)
                  Marker(
                    point: LatLng(camp.lat!, camp.lng!),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      key: ValueKey('veldCampMapPin_${camp.id}'),
                      onTap: () => _openCamp(camp),
                      child: Tooltip(
                        message: camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                        child: Icon(
                          Icons.location_pin,
                          size: 36,
                          color: theme.accentColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A schematic of the camps' relative positions.
  ///
  /// Map tiles need a network connection; the schematic does not, so an
  /// outfitter standing in a camp with no signal still sees how the camps sit
  /// relative to one another.
  Widget _layoutCard(
    ThemeController theme,
    List<Camp> located,
    VeldCampMapBounds bounds,
  ) {
    return Container(
      key: const ValueKey('veldCampLayoutSchematic'),
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'CAMP LAYOUT', theme: theme),
          const SizedBox(height: 4),
          Text(
            'Approximate positions — not to scale',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const dot = 22.0;
                const height = 180.0;
                final width = constraints.maxWidth;
                return Stack(
                  children: [
                    for (var index = 0; index < located.length; index++)
                      _layoutDot(
                        theme: theme,
                        camp: located[index],
                        index: index,
                        bounds: bounds,
                        width: width,
                        height: height,
                        dot: dot,
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < located.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${index + 1} · '
                '${located[index].name.isEmpty ? 'Unnamed camp' : located[index].name}',
                style: TextStyle(
                  color: OutfitterUi.subtitleColor(theme),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// One numbered dot on the schematic, positioned by the pure projection.
  Widget _layoutDot({
    required ThemeController theme,
    required Camp camp,
    required int index,
    required VeldCampMapBounds bounds,
    required double width,
    required double height,
    required double dot,
  }) {
    final position = VeldCampMapLayout.relativePosition(camp, bounds);
    return Positioned(
      left: (position.x * (width - dot)).clamp(0.0, width - dot),
      top: (position.y * (height - dot)).clamp(0.0, height - dot),
      child: GestureDetector(
        key: ValueKey('veldCampLayoutDot_${camp.id}'),
        onTap: () => _openCamp(camp),
        child: Container(
          width: dot,
          height: dot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.accentColor,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _unlocatedCard(ThemeController theme, List<Camp> unlocated) {
    return Container(
      key: const ValueKey('veldCampMapUnlocatedCard'),
      padding: const EdgeInsets.all(14),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeldCarrySectionLabel(label: 'NO LOCATION SET', theme: theme),
          const SizedBox(height: 6),
          Text(
            'No location set — open camp to set location',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          for (final camp in unlocated)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('veldCampMapUnlocated_${camp.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openCamp(camp),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_off_outlined,
                          size: 16,
                          color: OutfitterUi.subtitleColor(theme),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            camp.name.isEmpty ? 'Unnamed camp' : camp.name,
                            style: TextStyle(
                              color: theme.textColor,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: theme.accentColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _privacyNote(ThemeController theme) {
    return Row(
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: OutfitterUi.subtitleColor(theme),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Outfitter only. Camp locations are never shown to hunters.',
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageCard(ThemeController theme, String title, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.map_outlined, size: 42, color: theme.accentColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.titleColor(theme),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
