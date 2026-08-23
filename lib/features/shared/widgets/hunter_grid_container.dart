import 'package:flutter/material.dart';

/// Standardized responsive high-density grid layout for Hunter Mode tactical
/// modules -- the same max-extent grid the SA Game Guide uses for its rich
/// media species cards ([GameSpeciesCard]).
///
/// Wraps a [GridView.builder] with a
/// [SliverGridDelegateWithMaxCrossAxisExtent] so cards flow into as many
/// columns as the available width allows (1 column on phones, 2+ on tablets /
/// landscape), with consistent spacing, aspect ratio, and bottom safe-area
/// padding. Pair it with `HunterMediaCard` children (which carry the rounded
/// corners + warm amber glowing borders) for a consistent look across the
/// tactical modules.
class HunterGridContainer extends StatelessWidget {
  /// The card widgets laid out in the grid.
  final List<Widget> children;

  /// Optional trailing widget rendered after the last child (e.g. a
  /// [CopyrightFooter] centered in its own grid cell).
  final Widget? footer;

  /// Maximum width of a single grid cell (280 by default, matching the Game
  /// Guide). Smaller values increase the column density.
  final double maxCrossAxisExtent;

  /// Width/height ratio of each grid cell (0.72 by default, matching the Game
  /// Guide species cards).
  final double childAspectRatio;

  /// Spacing between grid cells, applied to both axes (16 by default).
  final double spacing;

  /// Outer padding of the grid. When null, a default of 16px on all sides is
  /// used with the bottom safe-area inset added automatically.
  final EdgeInsetsGeometry? padding;

  /// Scroll physics override (defaults to the platform-adaptive physics).
  final ScrollPhysics? physics;

  /// Whether the grid should size itself to its children (for embedding
  /// inside another scrollable). Defaults to false.
  final bool shrinkWrap;

  const HunterGridContainer({
    super.key,
    required this.children,
    this.footer,
    this.maxCrossAxisExtent = 280,
    this.childAspectRatio = 0.72,
    this.spacing = 16,
    this.padding,
    this.physics,
    this.shrinkWrap = false,
  });

  /// The standardized grid delegate so custom surfaces can reuse the exact
  /// same layout contract without this widget.
  static SliverGridDelegateWithMaxCrossAxisExtent gridDelegate({
    double maxCrossAxisExtent = 280,
    double childAspectRatio = 0.72,
    double spacing = 16,
  }) {
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCrossAxisExtent,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ??
        EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        );

    final itemCount = children.length + (footer != null ? 1 : 0);

    return GridView.builder(
      padding: effectivePadding,
      physics: physics,
      shrinkWrap: shrinkWrap,
      gridDelegate: gridDelegate(
        maxCrossAxisExtent: maxCrossAxisExtent,
        childAspectRatio: childAspectRatio,
        spacing: spacing,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (footer != null && index == children.length) {
          return Center(child: footer);
        }
        return children[index];
      },
    );
  }
}
