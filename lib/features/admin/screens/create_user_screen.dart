import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/user_management_service.dart';

/// Manual account creation screen for admins.
///
/// Form fields: Full Name, Email Address, Role (Hunter or Outfitter), Phone
/// Number, and Optional Details. On submit, creates the user document in
/// Firestore (`users/{uid}` or `outfitters/{uid}`) and triggers a password
/// reset / account setup email via `sendPasswordResetEmail`.
class CreateUserScreen extends StatefulWidget {
  final ThemeController theme;

  const CreateUserScreen({super.key, required this.theme});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _detailsController = TextEditingController();
  String _role = 'hunter';
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    final result = await UserManagementService.instance.provisionUser(
      fullName: _nameController.text,
      email: _emailController.text,
      role: _role,
      phoneNumber: _phoneController.text,
      optionalDetails: _detailsController.text.trim().isEmpty
          ? null
          : {'notes': _detailsController.text.trim()},
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    _showResultDialog(result);
  }

  void _showResultDialog(ProvisionResult result) {
    final success = result.success;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Text(success ? 'Account Created' : 'Creation Failed',
                style: TextStyle(color: widget.theme.textColor)),
          ],
        ),
        content: Text(
          success
              ? 'Provisioned ${result.fullName} (${result.email}) as ${result.role}.\n'
                  '${result.resetEmailSent ? "A password setup email has been sent." : "Password setup email could not be sent."}\n'
                  'UID: ${result.uid}'
              : (result.error ?? 'Unknown error'),
          style: TextStyle(color: widget.theme.textColor),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (success) {
                _nameController.clear();
                _emailController.clear();
                _phoneController.clear();
                _detailsController.clear();
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: widget.theme.backgroundColor,
          appBar: AppBar(
            title: const Text('Create User'),
            backgroundColor: widget.theme.backgroundColor,
            foregroundColor: widget.theme.textColor,
            elevation: 0,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter full name' : null,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter email';
                      if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$')
                          .hasMatch(v.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildRoleSelector(),
                  const SizedBox(height: 16),
                  _buildField(
                    controller: _detailsController,
                    label: 'Optional Details (notes)',
                    icon: Icons.notes,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(_submitting ? 'Creating...' : 'Create Account'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: widget.theme.subtitleColor),
        prefixIcon: Icon(icon, color: widget.theme.accentColor),
        filled: true,
        fillColor: widget.theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.theme.textColor.withAlpha(30)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.theme.textColor.withAlpha(30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.theme.accentColor, width: 1.5),
        ),
      ),
      style: TextStyle(color: widget.theme.textColor),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.theme.textColor.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: widget.theme.accentColor),
          const SizedBox(width: 12),
          Text('Role',
              style: TextStyle(
                color: widget.theme.textColor,
                fontWeight: FontWeight.bold,
              )),
          const Spacer(),
          _roleChip('hunter', 'Hunter'),
          const SizedBox(width: 8),
          _roleChip('outfitter', 'Outfitter'),
        ],
      ),
    );
  }

  Widget _roleChip(String value, String label) {
    final selected = _role == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _role = value),
      selectedColor: widget.theme.accentColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : widget.theme.textColor,
      ),
    );
  }
}
