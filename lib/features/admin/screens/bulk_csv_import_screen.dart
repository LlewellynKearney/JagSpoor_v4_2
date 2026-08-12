import 'dart:io';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:jagspoor/core/widgets/contextual_info_icon.dart';
import '../../../core/theme/app_theme.dart';
import '../services/user_management_service.dart';

/// Bulk CSV account importer for admins.
///
/// Accepts a CSV file with columns: `email`, `fullName`, `role`, `phoneNumber`.
/// Rows are processed sequentially, each provisioning a Firestore user document
/// (and triggering a password reset email). A summary log is produced, e.g.
/// "Successfully imported X accounts, Y errors".
class BulkCsvImportScreen extends StatefulWidget {
  final ThemeController theme;

  const BulkCsvImportScreen({super.key, required this.theme});

  @override
  State<BulkCsvImportScreen> createState() => _BulkCsvImportScreenState();
}

class _BulkCsvImportScreenState extends State<BulkCsvImportScreen> {
  bool _importing = false;
  final List<_ImportLogEntry> _log = [];
  int _successCount = 0;
  int _errorCount = 0;
  String? _selectedFileName;

  static const _expectedColumns = {'email', 'fullname', 'role', 'phonenumber'};

  Future<void> _pickAndImport() async {
    setState(() {
      _importing = true;
      _log.clear();
      _successCount = 0;
      _errorCount = 0;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }

      final file = result.files.first;
      _selectedFileName = file.name;

      String csvString;
      if (file.bytes != null) {
        csvString = String.fromCharCodes(file.bytes!);
      } else if (file.path != null) {
        csvString = await File(file.path!).readAsString();
      } else {
        _appendLog('No readable file content', success: false);
        setState(() => _importing = false);
        return;
      }

      await _processCsv(csvString);
    } catch (e) {
      _appendLog('Import failed: $e', success: false);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _processCsv(String csvString) async {
    List<List<dynamic>> rows;
    try {
      rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(csvString);
    } catch (e) {
      _appendLog('Failed to parse CSV: $e', success: false);
      return;
    }

    if (rows.isEmpty) {
      _appendLog('CSV file is empty', success: false);
      return;
    }

    // Resolve the header row (case-insensitive, whitespace-trimmed).
    final header = rows.first
        .map((c) => c.toString().trim().toLowerCase().replaceAll(' ', ''))
        .toList();
    final headerSet = header.toSet();
    final missing = _expectedColumns.difference(headerSet);
    if (missing.isNotEmpty) {
      _appendLog(
        'Missing required CSV columns: ${missing.join(', ')}. '
        'Expected: ${_expectedColumns.join(', ')}',
        success: false,
      );
      return;
    }

    final idxEmail = header.indexOf('email');
    final idxName = header.indexOf('fullname');
    final idxRole = header.indexOf('role');
    final idxPhone = header.indexOf('phonenumber');

    _appendLog('Found ${rows.length - 1} data row(s). Processing...');

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      String getCell(int idx) =>
          (idx >= 0 && idx < row.length) ? row[idx].toString().trim() : '';

      final email = getCell(idxEmail);
      final fullName = getCell(idxName);
      final role = getCell(idxRole).toLowerCase();
      final phoneNumber = getCell(idxPhone);

      if (email.isEmpty || fullName.isEmpty) {
        _errorCount++;
        _appendLog('Row $i: skipped (missing email or fullName)', success: false);
        continue;
      }

      final result = await UserManagementService.instance.provisionUser(
        fullName: fullName,
        email: email,
        role: role.isEmpty ? 'hunter' : role,
        phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
      );

      if (result.success) {
        _successCount++;
        _appendLog(
          'Row $i: ✓ $fullName ($email) — ${result.role}'
          '${result.resetEmailSent ? '' : ' (reset email pending)'}',
          success: true,
        );
      } else {
        _errorCount++;
        _appendLog(
          'Row $i: ✗ $email — ${result.error}',
          success: false,
        );
      }
    }

    _appendLog(
      'Import complete. Successfully imported $_successCount account(s), '
      '$_errorCount error(s).',
      success: _errorCount == 0,
    );
  }

  void _appendLog(String message, {bool? success}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _log.add(_ImportLogEntry(message: message, success: success));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: const Text('Bulk CSV Import'),
            backgroundColor: widget.theme.backgroundColor,
            foregroundColor: widget.theme.textColor,
            elevation: 0,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  color: widget.theme.cardColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: widget.theme.textColor.withAlpha(15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.description_outlined,
                                color: widget.theme.accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Expected CSV columns',
                                style: TextStyle(
                                  color: widget.theme.textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ContextualInfoIcon(
                              title: 'Bulk CSV Importer Column Spec',
                              iconColor: widget.theme.accentColor,
                              description:
                                  'The importer expects a header row containing the four columns below (case-insensitive, spaces ignored). Each subsequent row becomes one account; missing columns abort the import.',
                              concepts: const [
                                ExplanationConcept(
                                  label: 'email',
                                  detail: 'Unique login email — becomes the Firebase Auth username.',
                                ),
                                ExplanationConcept(
                                  label: 'fullName',
                                  detail: 'Display name written to the user profile.',
                                ),
                                ExplanationConcept(
                                  label: 'role',
                                  detail: 'Must be exactly "hunter" or "outfitter"; anything else fails validation.',
                                ),
                                ExplanationConcept(
                                  label: 'phoneNumber',
                                  detail: 'Contact number stored on the profile (used for 2FA SMS where enabled).',
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'email, fullName, role, phoneNumber',
                          style: TextStyle(
                            color: widget.theme.accentColor,
                            fontFamily: 'Mono',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'role must be "hunter" or "outfitter". '
                          'Rows are processed sequentially.',
                          style: TextStyle(
                            color: widget.theme.subtitleColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_selectedFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Selected: $_selectedFileName',
                      style: TextStyle(
                          color: widget.theme.subtitleColor, fontSize: 12),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _importing ? null : _pickAndImport,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(_importing ? 'Importing...' : 'Pick CSV & Import'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_log.isNotEmpty) ...[
                  Row(
                    children: [
                      _summaryChip('Success', _successCount, Colors.green),
                      const SizedBox(width: 12),
                      _summaryChip('Errors', _errorCount, Colors.red),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: widget.theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: widget.theme.textColor.withAlpha(15)),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _log
                          .map((e) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  e.message,
                                  style: TextStyle(
                                    color: e.success == null
                                        ? widget.theme.textColor
                                        : e.success!
                                            ? Colors.green
                                            : Colors.red,
                                    fontSize: 12,
                                    fontFamily: 'Mono',
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ImportLogEntry {
  final String message;
  final bool? success;

  _ImportLogEntry({required this.message, this.success});
}
