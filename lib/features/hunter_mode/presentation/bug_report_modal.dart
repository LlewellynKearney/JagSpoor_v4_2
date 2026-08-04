import 'package:flutter/material.dart';
import '../services/feedback_firebase_service.dart';

/// BugReportModal provides a bottom sheet form for submitting bug reports.
/// Dynamically styled via Theme.of(context) governed by Hunter Profile HUD settings.
class BugReportModal extends StatefulWidget {
  const BugReportModal({super.key});

  @override
  State<BugReportModal> createState() => _BugReportModalState();
}

class _BugReportModalState extends State<BugReportModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _stepsController = TextEditingController();
  String _selectedSeverity = 'Medium';
  bool _isSubmitting = false;

  static const List<String> _severityLevels = ['Low', 'Medium', 'Critical'];

  @override
  void dispose() {
    _titleController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final service = FeedbackFirebaseService();

      await service.submitBugReport(
        title: _titleController.text.trim(),
        steps: _stepsController.text.trim(),
        severity: _selectedSeverity,
      );

      final emailBody = FeedbackFirebaseService.buildBugReportEmailBody(
        title: _titleController.text.trim(),
        steps: _stepsController.text.trim(),
        severity: _selectedSeverity,
      );

      await service.launchNativeEmail(
        subject: '[Bug Report] ${_titleController.text.trim()}',
        body: emailBody,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit bug report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final cardBg = theme.cardColor;
    final textColor = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.bug_report_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '🪲 REPORT BUG',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bug Title Field
                  _buildSectionLabel('Bug Title', primaryColor),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    style: TextStyle(color: textColor),
                    decoration: _buildInputDecoration(
                      hintText: 'Enter a brief title for the bug',
                      prefixIcon: Icons.title,
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a bug title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Severity Level Dropdown
                  _buildSectionLabel('Severity Level', primaryColor),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSeverity,
                      dropdownColor: theme.scaffoldBackgroundColor,
                      style: TextStyle(color: primaryColor),
                      icon: Icon(Icons.arrow_drop_down, color: primaryColor),
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.warning_amber_rounded,
                          color: primaryColor,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      items:
                          _severityLevels.map((level) {
                            return DropdownMenuItem<String>(
                              value: level,
                              child: Text(
                                level,
                                style: TextStyle(
                                  color: _getSeverityColor(level, primaryColor),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedSeverity = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Steps to Reproduce Field
                  _buildSectionLabel('Steps to Reproduce', primaryColor),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _stepsController,
                    style: TextStyle(color: textColor),
                    maxLines: 4,
                    decoration: _buildInputDecoration(
                      hintText: 'Describe the steps to reproduce this bug...',
                      prefixIcon: Icons.format_list_numbered,
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please describe the steps to reproduce';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Submit Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submitBugReport,
                    child:
                        _isSubmitting
                            ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                            : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded),
                                SizedBox(width: 8),
                                Text(
                                  'Submit Bug Report',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color accentColor) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: accentColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    required ThemeData theme,
  }) {
    final primaryColor = theme.colorScheme.primary;
    final textColor = theme.colorScheme.onSurface;

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: textColor.withValues(alpha: 0.4)),
      prefixIcon: Icon(prefixIcon, color: primaryColor),
      filled: true,
      fillColor: theme.cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Color _getSeverityColor(String severity, Color fallbackColor) {
    switch (severity) {
      case 'Low':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'Critical':
        return Colors.red;
      default:
        return fallbackColor;
    }
  }
}
