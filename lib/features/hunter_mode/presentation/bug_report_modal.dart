import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jagspoor/core/services/image_service.dart';
import 'package:jagspoor/features/support/services/support_email_composer.dart';
import '../services/feedback_firebase_service.dart';

/// BugReportModal provides a bottom sheet form for submitting bug reports.
/// Dynamically styled via Theme.of(context) governed by Hunter Profile HUD settings.
///
/// Shared by Hunter Mode and Outfitter Mode: [mode] tags the submission's
/// originating portal ([FeedbackMode.hunter] by default) so the backend
/// record + support email reflect which mode the reporter was using.
class BugReportModal extends StatefulWidget {
  /// Maximum number of screenshot attachments a reporter may add.
  static const int maxScreenshots = 5;

  /// The app mode the report originates from ([FeedbackMode.hunter] by
  /// default; pass [FeedbackMode.outfitter] from the Outfitter portal).
  final String mode;

  const BugReportModal({super.key, this.mode = FeedbackMode.hunter});

  @override
  State<BugReportModal> createState() => _BugReportModalState();
}

class _BugReportModalState extends State<BugReportModal> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _stepsController = TextEditingController();
  String _selectedSeverity = 'Medium';
  bool _isSubmitting = false;

  // Screenshot attachments: picked local files awaiting upload on submit.
  final List<XFile> _attachedScreenshots = [];
  bool _isPickingImage = false;

  static const List<String> _severityLevels = ['Low', 'Medium', 'Critical'];

  @override
  void dispose() {
    _titleController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  bool get _canAddScreenshot =>
      _attachedScreenshots.length < BugReportModal.maxScreenshots;

  Future<void> _pickScreenshot(ImageSource source) async {
    if (!_canAddScreenshot) {
      _snack('Maximum ${BugReportModal.maxScreenshots} screenshots reached.',
          Colors.orange);
      return;
    }
    setState(() => _isPickingImage = true);
    try {
      final remaining =
          BugReportModal.maxScreenshots - _attachedScreenshots.length;
      if (source == ImageSource.gallery) {
        final picked = await ImagePicker().pickMultiImage(
          imageQuality: 80,
          limit: remaining,
        );
        if (picked.isNotEmpty) {
          setState(() {
            // Cap at the remaining slots in case the picker ignored `limit`.
            _attachedScreenshots.addAll(
                picked.take(BugReportModal.maxScreenshots -
                    _attachedScreenshots.length));
          });
        }
      } else {
        final picked = await ImagePicker().pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );
        if (picked != null) {
          setState(() => _attachedScreenshots.add(picked));
        }
      }
    } catch (e) {
      _snack(_friendlyPickerError(e), Colors.orange);
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _removeScreenshot(int index) {
    setState(() => _attachedScreenshots.removeAt(index));
  }

  /// Maps an image_picker / camera error to a concise, user-readable reason.
  String _friendlyPickerError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission') || msg.contains('denied')) {
      return 'Camera/photo permission denied. Enable it in your device settings.';
    }
    if (msg.contains('no_devices_found') || msg.contains('camera')) {
      return 'Camera unavailable on this device.';
    }
    if (msg.contains('unimplemented') || msg.contains('not supported')) {
      return 'Photo capture is not supported on this device.';
    }
    return 'Could not capture photo: $e';
  }

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final service = FeedbackFirebaseService();

      // Upload attached screenshots to Firebase Storage (best-effort: a
      // failed upload does not block the report itself).
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final List<String> screenshotUrls = [];
      for (var i = 0; i < _attachedScreenshots.length; i++) {
        try {
          final file = File(_attachedScreenshots[i].path);
          final compressed =
              await ImageService.compressExisting(file, quality: 75);
          final storagePath =
              'bug_report_attachments/$userId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final url = await ImageService.uploadCompressedPhoto(
              imageFile: compressed, storagePath: storagePath);
          screenshotUrls.add(url);
        } catch (e) {
          // Non-fatal: the report still submits, just without that image.
          debugPrint('BugReport: screenshot upload failed ($e)');
        }
      }

      await service.submitBugReport(
        title: _titleController.text.trim(),
        steps: _stepsController.text.trim(),
        severity: _selectedSeverity,
        screenshotUrls: screenshotUrls,
        mode: widget.mode,
      );

      // Build the automated support email (User ID + description + system
      // context) with Uri.encodeComponent-safe escaping, then hand off to the
      // native mail client via url_launcher.
      final mailtoUri = SupportEmailComposer.buildBugReportMailtoUri(
        userId: userId,
        title: _titleController.text.trim(),
        steps: _stepsController.text.trim(),
        severity: _selectedSeverity,
        mode: widget.mode,
      );
      final launched = await SupportEmailComposer.launch(mailtoUri);

      if (!mounted) return;
      if (!launched) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Report saved. No mail app found — please email support@jag-spoor.co.za manually.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
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

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
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
                      value: _selectedSeverity,
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
                  const SizedBox(height: 20),

                  // Screenshot attachments
                  _buildSectionLabel('Attach Screenshot (Optional)', primaryColor),
                  const SizedBox(height: 4),
                  Text(
                    'Add up to ${BugReportModal.maxScreenshots} screenshots as visual proof.',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _attachTile(
                          icon: Icons.photo_camera_rounded,
                          label: 'Take Photo',
                          theme: theme,
                          onTap: _isPickingImage || !_canAddScreenshot
                              ? null
                              : () => _pickScreenshot(ImageSource.camera),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _attachTile(
                          icon: Icons.add_photo_alternate_rounded,
                          label: 'Add from Gallery',
                          theme: theme,
                          onTap: _isPickingImage || !_canAddScreenshot
                              ? null
                              : () => _pickScreenshot(ImageSource.gallery),
                        ),
                      ),
                    ],
                  ),
                  if (_isPickingImage) ...[
                    const SizedBox(height: 8),
                    const Center(
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                  if (_attachedScreenshots.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachedScreenshots.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          return _screenshotThumbnail(
                            _attachedScreenshots[index],
                            index,
                            theme,
                          );
                        },
                      ),
                    ),
                  ],
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

  Widget _attachTile({
    required IconData icon,
    required String label,
    required ThemeData theme,
    required VoidCallback? onTap,
  }) {
    final primaryColor = theme.colorScheme.primary;
    final textColor = theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: primaryColor.withValues(alpha: onTap == null ? 0.15 : 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: onTap == null
                    ? textColor.withValues(alpha: 0.3)
                    : primaryColor,
                size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? textColor.withValues(alpha: 0.4)
                      : textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _screenshotThumbnail(
      XFile file, int index, ThemeData theme) {
    final primaryColor = theme.colorScheme.primary;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(file.path),
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 96,
              height: 96,
              color: theme.cardColor,
              child: Icon(Icons.broken_image_outlined,
                  color: primaryColor.withValues(alpha: 0.5)),
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _removeScreenshot(index),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
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
