import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Reusable in-app password change dialog.
///
/// Collects the current password, a new password, and a confirmation, then:
///   1. Validates the new password (min 8 chars) and that it matches the
///      confirmation (and differs from the current one).
///   2. Re-authenticates the user with [User.reauthenticateWithCredential]
///      using their email + the supplied current password.
///   3. Calls [User.updatePassword] on success.
///
/// Feedback is delivered via [SnackBar]s on the calling screen for both
/// success and re-authentication failures (e.g. wrong current password).
///
/// Show with [ChangePasswordDialog.show], which returns `true` when the
/// password was actually updated.
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  /// Opens the dialog over [context]. Returns `true` if the password was
  /// updated, `false`/`null` otherwise (cancelled or failed).
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      _notify(
        'No signed-in account found. Please sign in again.',
        isError: true,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // 1. Re-authenticate with the current password before any update.
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentController.text,
      );
      await user.reauthenticateWithCredential(credential);

      // 2. Update the password now that identity is confirmed.
      await user.updatePassword(_newController.text);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      _notify('Password updated successfully.');
    } on FirebaseAuthException catch (e) {
      _notify(_firebaseErrorMessage(e), isError: true);
    } catch (e) {
      _notify('Could not update password: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-credential-password':
        return 'Current password is incorrect. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'requires-recent-login':
        return 'For security, please sign out and back in, then try again.';
      case 'weak-password':
        return 'New password is too weak. Use at least 8 characters.';
      case 'operation-not-allowed':
        return 'Password updates are not enabled. Contact support.';
      default:
        return 'Could not update password: ${e.message ?? e.code}';
    }
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String? _validateNew(String? value) {
    final v = value ?? '';
    if (v.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (v == _currentController.text) {
      return 'New password must differ from the current one.';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if ((value ?? '').isEmpty) return 'Please confirm your new password.';
    if (value != _newController.text) return 'Passwords do not match.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_person_outlined, size: 26),
          SizedBox(width: 10),
          Text('Change Password'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(
                controller: _currentController,
                label: 'Current Password',
                obscure: _obscureCurrent,
                toggle: () => setState(
                    () => _obscureCurrent = !_obscureCurrent),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter your current password.' : null,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _newController,
                label: 'New Password',
                obscure: _obscureNew,
                toggle: () => setState(() => _obscureNew = !_obscureNew),
                validator: _validateNew,
                helper: 'At least 8 characters.',
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: _confirmController,
                label: 'Confirm New Password',
                obscure: _obscureConfirm,
                toggle: () => setState(
                    () => _obscureConfirm = !_obscureConfirm),
                validator: _validateConfirm,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Password'),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    required String? Function(String?) validator,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: toggle,
        ),
      ),
    );
  }
}
