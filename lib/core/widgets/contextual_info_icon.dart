import 'package:flutter/material.dart';

/// A small, reusable `(i)` info icon with subtle tactical-accent styling.
///
/// Tapping it opens an [ExplanationDialog] modal describing a complex feature
/// — keeping JagSpoor's tactical UI self-documenting without cluttering the
/// main control surfaces.
class ContextualInfoIcon extends StatelessWidget {
  const ContextualInfoIcon({
    super.key,
    required this.title,
    required this.description,
    this.concepts = const <ExplanationConcept>[],
    this.iconColor,
    this.iconSize = 18,
  });

  /// Dialog title, e.g. "Turret Click Math".
  final String title;

  /// Short prose description shown beneath the title.
  final String description;

  /// Key concepts / formula breakdown rendered as labelled rows.
  final List<ExplanationConcept> concepts;

  /// Override for the icon tint; defaults to the theme accent.
  final Color? iconColor;

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? Theme.of(context).colorScheme.primary;
    return IconButton(
      tooltip: title,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: iconSize + 8, minHeight: iconSize + 8),
      icon: Icon(Icons.info_outline, color: color, size: iconSize),
      onPressed: () => ExplanationDialog.show(
        context,
        title: title,
        description: description,
        concepts: concepts,
      ),
    );
  }
}

/// A single key-concept row for [ExplanationDialog]: a bolded label (often a
/// formula or metric name) with an explanation beneath it.
class ExplanationConcept {
  const ExplanationConcept({required this.label, required this.detail});

  final String label;
  final String detail;
}

/// Interactive modal that breaks down a complex feature into Title,
/// Description, and a list of Key Concepts / calculations, with a "Got it"
/// dismiss action.
class ExplanationDialog extends StatelessWidget {
  const ExplanationDialog({
    super.key,
    required this.title,
    required this.description,
    this.concepts = const <ExplanationConcept>[],
  });

  final String title;
  final String description;
  final List<ExplanationConcept> concepts;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String description,
    List<ExplanationConcept> concepts = const [],
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ExplanationDialog(
        title: title,
        description: description,
        concepts: concepts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.info_outline, color: accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (concepts.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'KEY CONCEPTS',
                style: TextStyle(
                  color: theme.textTheme.bodySmall?.color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              ...concepts.map((c) => _ConceptRow(concept: c)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'GOT IT',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConceptRow extends StatelessWidget {
  const _ConceptRow({required this.concept});
  final ExplanationConcept concept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(
              Icons.chevron_right,
              color: theme.colorScheme.primary,
              size: 16,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: '${concept.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: concept.detail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
