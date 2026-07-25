import 'package:flutter/material.dart';
import '../services/feedback_firebase_service.dart';

/// FeatureSuggestionModal provides a bottom sheet form for submitting
/// feature suggestions. Styled with Walnut Luxury backgrounds and
/// Thermal Glow accents.
class FeatureSuggestionModal extends StatefulWidget {
  const FeatureSuggestionModal({super.key});

  @override
  State<FeatureSuggestionModal> createState() => _FeatureSuggestionModalState();
}

class _FeatureSuggestionModalState extends State<FeatureSuggestionModal> {
  static const Color _walnutLuxury = Color(0xFF8B4513);
  static const Color _thermalGlow = Color(0xFFC5A059);
  static const Color _darkBackground = Color(0xFF1A1412);

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

      final emailBody = _buildEmailBody();
      await service.launchNativeEmail(
        subject: '[Feature Suggestion] ${_titleController.text.trim()}',
        body: emailBody,
      );

      if (!context.mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!context.mounted) return;
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

  String _buildEmailBody() {
    return '''
FEATURE SUGGESTION - Jagspoor Hunter Dashboard

Proposed Feature: ${_titleController.text.trim()}

Detailed Description:
${_descriptionController.text.trim()}

Expected Benefits to Hunting Teams:
${_benefitsController.text.trim()}

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
                        Icons.lightbulb_outline_rounded,
                        color: _thermalGlow,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '💡 SUGGEST NEW FEATURE',
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

                  // Proposed Feature Title Field
                  _buildSectionLabel('Proposed Feature Title'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _buildInputDecoration(
                      hintText: 'Enter a descriptive title for your feature',
                      prefixIcon: Icons.title,
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
                  _buildSectionLabel('Detailed Description'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 4,
                    decoration: _buildInputDecoration(
                      hintText: 'Describe your feature idea in detail...',
                      prefixIcon: Icons.description_outlined,
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
                  _buildSectionLabel('Expected Benefit to Hunting Teams'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _benefitsController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    decoration: _buildInputDecoration(
                      hintText: 'Explain how this feature would benefit hunting teams...',
                      prefixIcon: Icons.trending_up,
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
                      backgroundColor: _thermalGlow,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submitFeatureSuggestion,
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
}
