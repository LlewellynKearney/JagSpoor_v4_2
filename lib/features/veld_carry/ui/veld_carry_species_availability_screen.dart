import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// Availability band for a species count.
///
/// `10+` reads as good, `1..9` as limited, and `0` as not available (the
/// repository drops zero rows, so this is the defensive label rather than a
/// rendered state).
({String label, Color color}) speciesAvailabilityBadge(int count) {
  if (count >= 10) {
    return (label: 'Good availability', color: const Color(0xFF1B5E20));
  }
  if (count >= 1) {
    return (label: 'Limited availability', color: const Color(0xFFB26A00));
  }
  return (label: 'Not available', color: const Color(0xFF616161));
}

/// Hunter-facing species availability for one farm.
///
/// Renders ONLY the species name, its scientific name, the total head counted
/// and the camps it was counted on. It never renders a weight, a GU/BU split, a
/// camp size, a capacity figure, a coordinate or any location text, and it
/// never calls an ownership-gated repository method.
///
/// The data itself is gated twice: the repository fails closed unless the
/// hunter holds a confirmed / completed booking on the farm, and the whole
/// screen is only reachable through `VeldCarryGate`, so with the feature flag
/// OFF it cannot appear.
class VeldCarrySpeciesAvailabilityScreen extends StatefulWidget {
  const VeldCarrySpeciesAvailabilityScreen({
    super.key,
    required this.outfitterUid,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  /// The farm's outfitter — the owner segment of the veld data path. The
  /// hunter already has this from the package document it may read.
  final String outfitterUid;

  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in hunter's uid so widget tests can drive the
  /// screen against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarrySpeciesAvailabilityScreen> createState() =>
      _VeldCarrySpeciesAvailabilityScreenState();
}

class _VeldCarrySpeciesAvailabilityScreenState
    extends State<VeldCarrySpeciesAvailabilityScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<SpeciesAvailability> _species = const [];

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
    try {
      final species = await _repository.getSpeciesAvailabilityForHunter(
        widget.farmId,
        _currentUid(),
        outfitterUid: widget.outfitterUid,
      );
      if (!mounted) return;
      setState(() {
        _species = species;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load species availability: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return HunterScaffold(
      theme: theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Species Available',
              style: TextStyle(
                color: HunterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (widget.farmName != null && widget.farmName!.isNotEmpty)
              Text(
                widget.farmName!,
                style: TextStyle(
                  color: HunterUi.subtitleColor(theme),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme),
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
          _messageCard(theme, 'Could not load species availability', _error!),
          const CopyrightFooter(),
        ],
      );
    }
    if (_species.isEmpty) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          _messageCard(
            theme,
            'No species available yet',
            'The outfitter has not shared species availability for this farm.',
          ),
          const CopyrightFooter(),
        ],
      );
    }

    return ListView(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      children: [
        for (final species in _species) ...[
          _speciesCard(theme, species),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        _privacyNote(theme),
        const CopyrightFooter(),
      ],
    );
  }

  Widget _speciesCard(ThemeController theme, SpeciesAvailability species) {
    final badge = speciesAvailabilityBadge(species.totalCount);
    return Container(
      key: ValueKey('veldSpeciesAvailable_${species.speciesName}'),
      padding: const EdgeInsets.all(14),
      decoration: HunterUi.cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      species.speciesName,
                      style: TextStyle(
                        color: HunterUi.titleColor(theme),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (species.scientificName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          species.scientificName,
                          style: TextStyle(
                            color: HunterUi.subtitleColor(theme),
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              VeldCarryBadge(
                key: ValueKey(
                  'veldSpeciesAvailabilityBadge_${species.speciesName}',
                ),
                label: badge.label,
                color: badge.color,
                darkMode: theme.isDarkMode,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.pets_rounded,
                size: 15,
                color: theme.accentColor,
              ),
              const SizedBox(width: 6),
              Text(
                '${species.totalCount} counted',
                key: ValueKey(
                  'veldSpeciesAvailabilityCount_${species.speciesName}',
                ),
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.grass_rounded,
                size: 15,
                color: HunterUi.subtitleColor(theme),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  species.availableOnLabel,
                  style: TextStyle(
                    color: HunterUi.subtitleColor(theme),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
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
          color: HunterUi.subtitleColor(theme),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Species and counts only. Camp locations, stock weights and '
            'private permits are never shared.',
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
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
      decoration: HunterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.pets_rounded, size: 42, color: theme.accentColor),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HunterUi.titleColor(theme),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HunterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
