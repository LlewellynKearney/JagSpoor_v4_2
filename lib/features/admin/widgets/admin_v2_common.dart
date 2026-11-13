import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Formats a count for a KPI card, abbreviating thousands (`1234` → `1.2k`).
String formatAdminCount(int value) {
  if (value >= 1000) {
    final k = value / 1000;
    return k == k.roundToDouble()
        ? '${k.toInt()}k'
        : '${k.toStringAsFixed(1)}k';
  }
  return value.toString();
}

/// A titled KPI card shared by every Admin Portal V2 page.
///
/// A `null` [value] with a [valueLabel] renders the label (e.g. a percentage
/// or a ZAR amount); a `null` [value] with no label renders an em dash.
class AdminV2MetricCard extends StatelessWidget {
  final ThemeController theme;
  final IconData icon;
  final String label;
  final int? value;
  final String? valueLabel;
  final String? caption;

  const AdminV2MetricCard({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    this.value,
    this.valueLabel,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.textColor.withAlpha(15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: theme.subtitleColor, fontSize: 12),
                ),
              ),
            ],
          ),
          Text(
            valueLabel ?? (value == null ? '—' : formatAdminCount(value!)),
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.subtitleColor, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

/// A fixed 4-column KPI grid (the dashboard rows + each page's summary grid).
class AdminV2MetricGrid extends StatelessWidget {
  final List<Widget> children;

  const AdminV2MetricGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: children,
    );
  }
}

/// A titled table card. Renders [emptyLabel] when [rows] is empty so a zero
/// state is always explicit (never a blank card).
class AdminV2TableCard extends StatelessWidget {
  final ThemeController theme;
  final String title;
  final String emptyLabel;
  final List<String> headers;
  final List<List<String>> rows;

  const AdminV2TableCard({
    super.key,
    required this.theme,
    required this.title,
    required this.emptyLabel,
    required this.headers,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(
                emptyLabel,
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 480),
                  child: Table(
                    columnWidths: {
                      for (var i = 0; i < headers.length; i++)
                        i: i == 0
                            ? const FlexColumnWidth(2)
                            : const FlexColumnWidth(),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: theme.textColor.withAlpha(12),
                      ),
                    ),
                    children: [
                      TableRow(
                        children: [
                          for (final h in headers)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                h,
                                style: TextStyle(
                                  color: theme.accentColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      for (final row in rows)
                        TableRow(
                          children: [
                            for (final cell in row)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  cell,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.textColor,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A titled key/value breakdown card (province / plan / status breakdowns).
class AdminV2BreakdownCard extends StatelessWidget {
  final ThemeController theme;
  final String title;
  final List<MapEntry<String, String>> entries;
  final String? note;

  const AdminV2BreakdownCard({
    super.key,
    required this.theme,
    required this.title,
    required this.entries,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.textColor.withAlpha(15)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: theme.subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      entry.value,
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  note!,
                  style: TextStyle(color: theme.subtitleColor, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bold accent section header.
class AdminV2SectionHeader extends StatelessWidget {
  final ThemeController theme;
  final String title;

  const AdminV2SectionHeader({
    super.key,
    required this.theme,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          color: theme.accentColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A single-select chip row for a page's filter (status / role / etc.).
class AdminV2FilterChipBar<T> extends StatelessWidget {
  final ThemeController theme;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final String keyPrefix;

  /// Optional key suffix override (defaults to the value's `toString()`), so a
  /// caller can supply a stable, non-`Enum.toString` key (e.g. `value.name`).
  final String Function(T)? keyOf;

  const AdminV2FilterChipBar({
    super.key,
    required this.theme,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    required this.keyPrefix,
    this.keyOf,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            key: ValueKey('$keyPrefix${keyOf?.call(v) ?? v}'),
            label: Text(labelOf(v)),
            selected: selected == v,
            onSelected: (_) => onSelected(v),
            selectedColor: theme.accentColor.withAlpha(60),
            labelStyle: TextStyle(
              color: selected == v ? theme.textColor : theme.subtitleColor,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: theme.cardColor,
            side: BorderSide(color: theme.textColor.withAlpha(20)),
          ),
      ],
    );
  }
}

/// A compact search field used by the Users page.
class AdminV2SearchField extends StatelessWidget {
  final ThemeController theme;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const AdminV2SearchField({
    super.key,
    required this.theme,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search…',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: theme.textColor, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: theme.subtitleColor, fontSize: 13),
        prefixIcon: Icon(Icons.search, color: theme.subtitleColor, size: 20),
        isDense: true,
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.textColor.withAlpha(20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.textColor.withAlpha(20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.accentColor),
        ),
      ),
    );
  }
}

/// A small inline info note (icon + text) used under grids/tables.
class AdminV2Note extends StatelessWidget {
  final ThemeController theme;
  final String text;

  const AdminV2Note({super.key, required this.theme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: theme.subtitleColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.subtitleColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
