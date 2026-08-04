import 'package:flutter/material.dart';
import '../services/feedback_firebase_service.dart';

/// FeatureSuggestionModal provides a bottom sheet form for submitting
/// feature suggestions. Dynamically styled via Theme.of(context) governed
/// by Hunter Profile HUD settings.
class FeatureSuggestionModal extends StatefulWidget {
  const FeatureSuggestionModal({super.key});

  @override
  State<FeatureSuggestionModal> createState() => _FeatureSuggestionModalState();
}

class _FeatureSuggestionModalState extends State<FeatureSuggestionModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _benefitsController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _benefitsController.dispose();
    super.dispose();
  }

  Future<void> _submitFeatureSuggestion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final service = FeedbackFirebaseService();

      await service.submitFeatureSuggestion(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        benefits: _benefitsController.text.trim(),
      );

      final emailBody = FeedbackFirebaseService.buildFeatureSuggestionEmailBody(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        benefits: _benefitsController.text.trim(),
      );

      await service.launchNativeEmail(
        subject: '[Feature Suggestion] ${_titleController.text.trim()}',
        body: emailBody,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit feature suggestion: $e'),
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
                        Icons.lightbulb_outline_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '💡 SUGGEST NEW FEATURE',
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

                  // Proposed Feature Title Field
                  _buildSectionLabel('Proposed Feature Title', primaryColor),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    style: TextStyle(color: textColor),
                    decoration: _buildInputDecoration(
                      hintText: 'Enter a descriptive title for your feature',
                      prefixIcon: Icons.title,
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a feature title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Detailed Description Field
                  _buildSectionLabel('Detailed Description', primaryColor),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    style: TextStyle(color: textColor),
                    maxLines: 4,
                    decoration: _buildInputDecoration(
                      hintText: 'Describe your feature idea in detail...',
                      prefixIcon: Icons.description_outlined,
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide a detailed description';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Expected Benefits Field
                  _buildSectionLabel(
                    'Expected Benefit to Hunting Teams',
                    primaryColor,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _benefitsController,
                    style: TextStyle(color: textColor),
                    maxLines: 3,
                    decoration: _buildInputDecoration(
                      hintText:
                          'Explain how this feature would benefit hunting teams...',
                      prefixIcon: Icons.trending_up,
                      theme: theme,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please describe the expected benefits';
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
                    onPressed: _isSubmitting ? null : _submitFeatureSuggestion,
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
                                  'Submit Feature Suggestion',
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
}
