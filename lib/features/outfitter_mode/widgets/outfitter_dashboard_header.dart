import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../shared/widgets/hunter_media_card.dart';

/// Frosted, two-line branded header for the Outfitter Mode dashboard.
///
/// Replaces the previous single static `Text('JagSpoor Outfitter')` AppBar
/// title (which truncated at the action buttons on narrow devices) with a
/// structured layout:
///
/// - a bold header-caps `JAGSPOOR` wordmark (wrapped in a [FittedBox] with
///   [BoxFit.scaleDown] so it can never clip, regardless of device width),
/// - a stylized amber `OUTFITTER MODE` sub-badge carrying a subtle glowing
///   status dot that reflects the live outfitter sync state,
/// - a compact trailing action group (8px rhythm) rendered via
///   [HunterFrostedCircleButton] chips so the title keeps maximum width.
///
/// The header floats over the bushveld wallpaper on a frosted dark backdrop
/// (`#1E1E1E` at ~82% opacity + ambient blur + warm bottom hairline).
class OutfitterDashboardHeader extends StatelessWidget
    implements PreferredSizeWidget {
  /// The outfitter brand title (bold header caps).
  static const String brandTitle = 'JAGSPOOR';

  /// The outfitter sub-badge label (manager branch still reads
  /// "FARM MANAGER MODE").
  static const String outfitterBadge = 'OUTFITTER MODE';

  /// The farm-manager sub-badge label.
  static const String managerBadge = 'FARM MANAGER MODE';

  /// The frosted dark backdrop color.
  static const Color backdropColor = Color(0xD11E1E1E);

  /// Whether the caller is signed in as a farm manager (drives the badge
  /// label).
  final bool isManager;

  /// Whether outfitter dashboard sync is active (drives the glowing status
  /// dot — warm amber when live, muted grey when offline).
  final bool syncActive;

  /// The trailing action buttons (already wrapped in frosted chips).
  final List<Widget> actions;

  const OutfitterDashboardHeader({
    super.key,
    required this.isManager,
    this.syncActive = true,
    this.actions = const [],
  });

  /// The badge label for the current role branch.
  String get badgeLabel => isManager ? managerBadge : outfitterBadge;

  /// The status dot color (warm amber when sync is live).
  Color get syncDotColor =>
      syncActive ? kHunterMediaAmber : const Color(0xFF8A8A8A);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: backdropColor,
            border: Border(
              bottom: BorderSide(
                color: kHunterMediaAmber.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title block: brand wordmark + mode sub-badge. Expanded so
                  // the action group always keeps its chips; the FittedBox
                  // scale-down guarantees no truncation on narrow widths.
                  Expanded(child: _buildTitleBlock(context)),
                  const SizedBox(width: 8),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBlock(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            brandTitle,
            key: const ValueKey('outfitterHeaderBrandTitle'),
            maxLines: 1,
            style: TextStyle(
              // The frosted dark backdrop is constant across Day/Night, so
              // the wordmark stays crisp white in both modes.
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 2.6,
              height: 1.0,
              shadows: isDark
                  ? [
                      Shadow(
                        color: kHunterMediaAmber.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 3),
        _ModeBadge(label: badgeLabel, syncActive: syncActive),
      ],
    );
  }
}

/// The stylized `OUTFITTER MODE` sub-badge: a glowing sync-status dot plus
/// amber letter-spaced caps on a translucent amber pill.
class _ModeBadge extends StatelessWidget {
  final String label;
  final bool syncActive;

  const _ModeBadge({required this.label, required this.syncActive});

  @override
  Widget build(BuildContext context) {
    final dotColor =
        syncActive ? kHunterMediaAmber : const Color(0xFF8A8A8A);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        return Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: kHunterMediaAmber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: kHunterMediaAmber.withValues(alpha: 0.45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing status dot: warm amber halo when sync is live, a
              // plain muted dot when offline.
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: syncActive
                      ? [
                          BoxShadow(
                            color: kHunterMediaAmber.withValues(alpha: 0.8),
                            blurRadius: 5,
                            spreadRadius: 0.5,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              // Loose flex: the label keeps its natural width when it fits
              // (the pill hugs its content) and fades instead of overflowing
              // on the narrowest devices.
              Flexible(
                child: Text(
                  label,
                  key: const ValueKey('outfitterHeaderModeBadge'),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    color: kHunterMediaAmber,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
