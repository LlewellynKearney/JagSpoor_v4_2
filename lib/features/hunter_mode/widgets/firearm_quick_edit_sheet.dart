import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';

/// Result of a successful quick-edit: the edited detail values as strings.
///
/// Callers merge this into their `Map<String, String>` firearm representation
/// (the Digital Firearm Safe + detail screen store detail fields as strings).
class FirearmQuickEditResult {
  final String make;
  final String model;
  final String caliber;
  final String serial;

  const FirearmQuickEditResult({
    required this.make,
    required this.model,
    required this.caliber,
    required this.serial,
  });
}

/// Modal bottom sheet that lets the hunter edit the core firearm details
/// (Make / Model / Caliber / Serial Number) directly, without leaving the
/// Digital Firearm Safe or opening the full capture-led manual form.
///
/// Returns a [FirearmQuickEditResult] via `Navigator.pop` on save, or `null`
/// when dismissed.
class FirearmQuickEditSheet extends StatefulWidget {
  final ThemeController theme;

  /// Current values to pre-fill (keyed by the safe's string-map field names:
  /// `make` / `model` / `caliber` / `serial`).
  final Map<String, String> firearm;

  /// Optional explicit title; defaults to "Edit Firearm Details".
  final String title;

  const FirearmQuickEditSheet({
    super.key,
    required this.theme,
    required this.firearm,
    this.title = 'Edit Firearm Details',
  });

  /// Convenience launcher: pushes the sheet as a modal bottom sheet and
  /// awaits the edited result (null when dismissed).
  static Future<FirearmQuickEditResult?> show(
    BuildContext context, {
    required ThemeController theme,
    required Map<String, String> firearm,
    String title = 'Edit Firearm Details',
  }) {
    return showModalBottomSheet<FirearmQuickEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FirearmQuickEditSheet(
        theme: theme,
        firearm: firearm,
        title: title,
      ),
    );
  }

  @override
  State<FirearmQuickEditSheet> createState() => _FirearmQuickEditSheetState();
}

class _FirearmQuickEditSheetState extends State<FirearmQuickEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _caliber;
  late final TextEditingController _serial;

  @override
  void initState() {
    super.initState();
    final f = widget.firearm;
    _make = TextEditingController(text: f['make'] ?? '');
    _model = TextEditingController(text: f['model'] ?? '');
    _caliber = TextEditingController(
      text: f['caliber'] ?? f['calibre'] ?? '',
    );
    _serial = TextEditingController(text: f['serial'] ?? '');
  }

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _caliber.dispose();
    _serial.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      FirearmQuickEditResult(
        make: _make.text.trim(),
        model: _model.text.trim(),
        caliber: _caliber.text.trim(),
        serial: _serial.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: HunterUi.cardColor(theme),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.subtitleColor.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: HunterUi.titleColor(theme),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          color: theme.subtitleColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Edit the firearm details below. Changes are saved to your '
                    'Digital Firearm Safe immediately.',
                    style: TextStyle(
                      fontSize: 12,
                      color: HunterUi.subtitleColor(theme),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('quickEditMakeField'),
                    controller: _make,
                    decoration: InputDecoration(
                      labelText: 'Make / Brand',
                      hintText: 'e.g., TIKKA T3X',
                      prefixIcon: const Icon(
                        Icons.precision_manufacturing_outlined,
                      ),
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Make is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('quickEditModelField'),
                    controller: _model,
                    decoration: InputDecoration(
                      labelText: 'Model',
                      hintText: 'e.g., T3X Tactical',
                      prefixIcon: const Icon(Icons.tag),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('quickEditCaliberField'),
                    controller: _caliber,
                    decoration: InputDecoration(
                      labelText: 'Caliber',
                      hintText: 'e.g., .308 Win',
                      prefixIcon: const Icon(Icons.gps_fixed),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('quickEditSerialField'),
                    controller: _serial,
                    decoration: InputDecoration(
                      labelText: 'Serial Number',
                      hintText: 'e.g., OB14468',
                      prefixIcon: const Icon(Icons.numbers),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    key: const ValueKey('quickEditSaveButton'),
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: theme.isDarkMode
                          ? Colors.black
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text(
                      'SAVE CHANGES',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}