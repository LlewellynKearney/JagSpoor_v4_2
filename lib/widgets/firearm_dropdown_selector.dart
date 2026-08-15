import 'package:flutter/material.dart';

import '../features/ballistics/data/models/rifle_profile.dart';

/// Reusable firearm selector backed by the Digital Firearm Safe.
///
/// Renders a `DropdownButtonFormField<String>` whose [value] is bound to the
/// unique string [RifleProfile.id] (never an object reference), so a
/// `DropdownButtonFormField` assertion error ("value not in items") can never
/// fire when the underlying list changes (e.g. a firearm is deleted while the
/// dropdown is open). The [selectedFirearmId] is validated against the live
/// [firearms] list on every build and coerced to `null` when it is absent.
///
/// Visual states:
/// - [isLoading] == true  -> a thin `LinearProgressIndicator` replaces the
///   dropdown while the firearm list is being fetched.
/// - [firearms] is empty   -> a disabled `TextFormField` with the hint
///   "No firearms found in Safe" (the dropdown is hidden so no orphan value
///   can be shown).
/// - otherwise             -> the live dropdown, expanded to fill the row,
///   each item labelled with `RifleProfile.displayName`
///   ("make model (calibre)").
///
/// The widget is stateless: all selection state is owned by the parent
/// (controlled component), and changes are reported via [onChanged]. This
/// makes it safe to embed inside a gesture-consuming layer (e.g. an
/// `InteractiveViewer` / tap canvas) — because the dropdown is a leaf widget
/// built fresh each frame with a `ValueKey` derived from the effective value,
/// its tap handling stays responsive and is not starved by an ancestor
/// gesture detector (the parent should still place this widget ABOVE / OUTSIDE
/// any `InteractiveViewer` stack so the ancestor never intercepts the tap in
/// the first place; see the Shot Group Target Analyzer screen).
class FirearmDropdownSelector extends StatelessWidget {
  /// The currently-selected firearm's document id, or `null` if nothing is
  /// selected. Validated against [firearms] on every build — an id that no
  /// longer exists in the list is coerced to `null` to prevent the
  /// `DropdownButtonFormField` "value not in items" assertion.
  final String? selectedFirearmId;

  /// The live list of firearms from the Digital Firearm Safe provider
  /// (typically `InventoryBridge.watchSafeFirearms()`).
  final List<RifleProfile> firearms;

  /// When `true`, a `LinearProgressIndicator` is shown instead of the
  /// dropdown (e.g. while the first snapshot is still loading).
  final bool isLoading;

  /// Called with the newly-selected firearm id, or `null` if the user
  /// cleared the selection. Not called while [isLoading] is true or when
  /// [firearms] is empty (the dropdown is disabled in those states).
  final ValueChanged<String?> onChanged;

  /// Optional trailing widget rendered after the dropdown (e.g. a turret-unit
  /// context `Chip`). Hidden while loading or when the list is empty.
  final Widget? trailing;

  /// Optional leading icon (defaults to a firearm/link icon). Override to
  /// match the host screen's iconography.
  final IconData leadingIcon;

  const FirearmDropdownSelector({
    super.key,
    required this.selectedFirearmId,
    required this.firearms,
    required this.onChanged,
    this.isLoading = false,
    this.trailing,
    this.leadingIcon = Icons.gpp_good_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final textPrimary = theme.textTheme.bodyLarge?.color ?? const Color(0xFFE0E0E0);
    final textSecondary =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7) ??
            const Color(0xFFB0B0B0);
    final cardColor = theme.cardColor;

    // Validate the selection against the live list BEFORE binding it to the
    // dropdown value. A stale id (e.g. the firearm was just deleted) is
    // coerced to null so `DropdownButtonFormField` never asserts.
    final effectiveValue = (selectedFirearmId != null &&
            firearms.any((r) => r.id == selectedFirearmId))
        ? selectedFirearmId
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            // Loading state: a thin progress bar replaces the dropdown so the
            // row never collapses to zero height while the first snapshot is
            // in flight.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(leadingIcon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: accent.withValues(alpha: 0.15),
                      color: accent,
                    ),
                  ),
                ],
              ),
            )
          else if (firearms.isEmpty)
            // Empty state: a disabled TextFormField with the canonical hint
            // (not an interactive dropdown, so no orphan value can render and
            // no tap target is offered when there is nothing to select).
            TextFormField(
              enabled: false,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon:
                    Icon(leadingIcon, size: 18, color: accent),
                hintText: 'No firearms found in Safe',
                hintStyle: TextStyle(color: accent, fontSize: 13),
              ),
              style: TextStyle(color: textSecondary, fontSize: 13),
            )
          else
            // Live dropdown. `ValueKey` derived from the effective value forces
            // the FormFieldState to reinitialise whenever the selection
            // changes — `DropdownButtonFormField` only reads `value` once on
            // first build, so without the key the displayed selection would
            // drift out of sync with the parent state on a re-build.
            Row(
              children: [
                Icon(leadingIcon, size: 18, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String?>(effectiveValue),
                      value: effectiveValue,
                      isExpanded: true,
                      dropdownColor: cardColor,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      hint: Text(
                        'Choose Firearm',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      items: firearms
                          .map((r) => DropdownMenuItem<String>(
                                value: r.id,
                                child: Text(
                                  r.displayName,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: onChanged,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
        ],
      ),
    );
  }
}
