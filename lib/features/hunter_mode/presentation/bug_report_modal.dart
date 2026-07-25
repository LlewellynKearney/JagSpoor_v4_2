import 'package:flutter/material.dart';
import '../services/feedback_firebase_service.dart';

/// BugReportModal provides a bottom sheet form for submitting bug reports.
/// Styled with Walnut Luxury backgrounds and Thermal Glow accents.
class BugReportModal extends StatefulWidget {
  const BugReportModal({super.key});

  @override
  State<BugReportModal> createState() => _BugReportModalState();
}

class _BugReportModalState extends State<BugReportModal> {
  static const Color _walnutLuxury = Color(0xFF8B4513);
  static const Color _thermalGlow = Color(0xFFC5A059);
  static const Color _darkBackground = Color(0xFF1A1412);

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

      final emailBody = _buildEmailBody();
      await service.launchNativeEmail(
        subject: '[Bug Report] ${_titleController.text.trim()}',
        body: emailBody,
      );

      if (!context.mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!context.mounted) return;
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

  String _buildEmailBody() {
    return '''
BUG REPORT - Jagspoor Hunter Dashboard

Title: ${_titleController.text.trim()}

Severity Level: $_selectedSeverity

Steps to Reproduce:
${_stepsController.text.trim()}

---
Submitted via Jagspoor App
''';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _darkBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: _thermalGlow.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom +
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
                      const Icon(
                        Icons.bug_report_rounded,
                        color: _thermalGlow,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '🪲 REPORT BUG',
                          style: TextStyle(
                            color: _thermalGlow,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bug Title Field
                  _buildSectionLabel('Bug Title'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(
                      hintText: 'Enter a brief title for the bug',
                      prefixIcon: Icons.title,
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
                  _buildSectionLabel('Severity Level'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _walnutLuxury.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _thermalGlow.withValues(alpha: 0.3),
                      ),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: _selectedSeverity,
                      dropdownColor: _darkBackground,
                      style: const TextStyle(color: _thermalGlow),
                      icon: const Icon(Icons.arrow_drop_down, color: _thermalGlow),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.warning_amber_rounded, color: _thermalGlow),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      items: _severityLevels.map((level) {
                        return DropdownMenuItem<String>(
                          value: level,
                          child: Text(
                            level,
                            style: TextStyle(
                              color: _getSeverityColor(level),
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
                  _buildSectionLabel('Steps to Reproduce'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _stepsController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 4,
                    decoration: _buildInputDecoration(
                      hintText: 'Describe the steps to reproduce this bug...',
                      prefixIcon: Icons.format_list_numbered,
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
                      backgroundColor: _thermalGlow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submitBugReport,
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
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

  Widget _buildSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _thermalGlow,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
      prefixIcon: Icon(prefixIcon, color: _thermalGlow),
      filled: true,
      fillColor: _walnutLuxury.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _thermalGlow.withValues(alpha: 0.3),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: _thermalGlow.withValues(alpha: 0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: _thermalGlow,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Colors.red,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'Low':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      case 'Critical':
        return Colors.red;
      default:
        return _thermalGlow;
    }
  }
}
