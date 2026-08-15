import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:signature/signature.dart';
import '../../../core/theme/app_theme.dart';
import '../models/venison_transport_permit.dart';
import '../services/venison_permit_manager.dart';

/// Legal South African Venison / Game Transport & Hunt Permit form.
///
/// Renders the official SA statutory template with dual digital signature pads
/// (Hunter + Authorized Person / Outfitter), JagSpoor branding in the header,
/// and a multi-species "Species Hunted and Transported" checklist. When opened
/// in the context of an active [bookingId] it pre-fills hunter + outfitter/farm
/// details (still editable) via [VenisonPermitManager.prefillFromBooking].
class VenisonPermitFormScreen extends StatefulWidget {
  final ThemeController theme;

  /// Optional booking context — when supplied the form pre-fills hunter +
  /// outfitter/farm details from the booking and linked user/outfitter docs.
  final String? bookingId;

  /// When true the form is presented in outfitter mode (the outfitter is the
  /// issuer). Otherwise it is presented in hunter mode. Determines which party
  /// is treated as the primary signer and the permit's `outfitterId`.
  final bool isOutfitterMode;

  /// Optional raw prefill map applied directly (no Firestore lookup). When set
  /// it takes precedence over [bookingId] and seeds the hunter block + species
  /// list from the supplied map.
  final Map<String, dynamic>? prefillData;

  const VenisonPermitFormScreen({
    super.key,
    required this.theme,
    this.bookingId,
    this.isOutfitterMode = true,
    this.prefillData,
  });

  @override
  State<VenisonPermitFormScreen> createState() =>
      _VenisonPermitFormScreenState();
}

class _VenisonPermitFormScreenState extends State<VenisonPermitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _permitManager = VenisonPermitManager.instance;

  // Dual signature controllers
  final SignatureController _hunterSignatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  final SignatureController _outfitterSignatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // Hunter block controllers
  final _hunterNameController = TextEditingController();
  final _hunterIdController = TextEditingController();
  final _hunterCellController = TextEditingController();
  final _hunterAddressController = TextEditingController();

  // Authorized Person / Farm block controllers
  final _authorizedPersonController = TextEditingController();
  final _farmNameController = TextEditingController();
  final _farmAddressController = TextEditingController();
  final _farmCellController = TextEditingController();

  // Hunt window
  DateTime? _huntStartDate;
  DateTime? _huntEndDate;

  // Species hunted and transported
  final List<Map<String, dynamic>> _speciesList = [];

  // Prefill metadata
  String? _prefillOutfitterId;
  String? _prefillHunterId;

  // State
  bool _isSubmitting = false;
  bool _isPrefilling = true;

  @override
  void initState() {
    super.initState();
    _loadPrefill();
  }

  @override
  void dispose() {
    _hunterNameController.dispose();
    _hunterIdController.dispose();
    _hunterCellController.dispose();
    _hunterAddressController.dispose();
    _authorizedPersonController.dispose();
    _farmNameController.dispose();
    _farmAddressController.dispose();
    _farmCellController.dispose();
    _hunterSignatureController.dispose();
    _outfitterSignatureController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefill() async {
    // Default the outfitter id to the current user in outfitter mode.
    final currentUser = FirebaseAuth.instance.currentUser;
    if (widget.isOutfitterMode && currentUser != null) {
      _prefillOutfitterId = currentUser.uid;
    }

    // Direct prefill map (takes precedence over the booking lookup — it
    // already carries the harvested species list).
    if (widget.prefillData != null) {
      final p = widget.prefillData!;
      if (!mounted) return;
      setState(() {
        _hunterNameController.text = p['hunterName'] ?? '';
        _hunterCellController.text = p['hunterCell'] ?? '';
        _hunterAddressController.text = p['hunterAddress'] ?? '';
        _hunterIdController.text = p['hunterIdNumber'] ?? '';
        _authorizedPersonController.text = p['authorizedPersonName'] ?? '';
        _farmNameController.text = p['farmName'] ?? '';
        _farmAddressController.text = p['farmAddress'] ?? '';
        _farmCellController.text = p['farmCell'] ?? '';
        _prefillOutfitterId = p['outfitterId'] ?? _prefillOutfitterId;
        final species =
            p['speciesHuntedAndTransported'] as List<dynamic>?;
        if (species != null) {
          _speciesList.addAll(
            species
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e)),
          );
        }
      });
      if (mounted) setState(() => _isPrefilling = false);
      return;
    }

    if (widget.bookingId != null) {
      try {
        final prefill = await _permitManager.prefillFromBooking(widget.bookingId!);
        if (!mounted) return;
        setState(() {
          _hunterNameController.text = prefill['hunterName'] ?? '';
          _hunterCellController.text = prefill['hunterCell'] ?? '';
          _hunterAddressController.text = prefill['hunterAddress'] ?? '';
          _hunterIdController.text = prefill['hunterIdNumber'] ?? '';
          _authorizedPersonController.text = prefill['authorizedPersonName'] ?? '';
          _farmNameController.text = prefill['farmName'] ?? '';
          _farmAddressController.text = prefill['farmAddress'] ?? '';
          _farmCellController.text = prefill['farmCell'] ?? '';
          _prefillOutfitterId = prefill['outfitterId'] ?? _prefillOutfitterId;
          _prefillHunterId = prefill['hunterId'];
        });
      } catch (_) {
        // Prefill is best-effort; the user can still fill manually.
      }
    }
    if (mounted) setState(() => _isPrefilling = false);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _huntStartDate = picked;
        } else {
          _huntEndDate = picked;
        }
      });
    }
  }

  void _addSpecies() {
    showDialog(
      context: context,
      builder: (context) => _AddSpeciesDialog(
        onAdd: (species) => setState(() => _speciesList.add(species)),
      ),
    );
  }

  void _removeSpecies(int index) {
    setState(() => _speciesList.removeAt(index));
  }

  Future<void> _submitPermit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_speciesList.isEmpty) {
      _showSnack('Please add at least one species hunted and transported',
          isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Capture both signatures (either may be empty if one party signs later).
      Uint8List? hunterSig;
      Uint8List? outfitterSig;
      if (_hunterSignatureController.isNotEmpty) {
        hunterSig = await _hunterSignatureController.toPngBytes();
      }
      if (_outfitterSignatureController.isNotEmpty) {
        outfitterSig = await _outfitterSignatureController.toPngBytes();
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      final permit = VenisonTransportPermit(
        permitNumber: _permitManager.generatePermitNumber(),
        outfitterId: _prefillOutfitterId ?? currentUser?.uid ?? '',
        hunterId: _prefillHunterId,
        bookingId: widget.bookingId,
        hunterName: _hunterNameController.text.trim(),
        hunterIdNumber: _hunterIdController.text.trim(),
        hunterCell: _hunterCellController.text.trim(),
        hunterAddress: _hunterAddressController.text.trim(),
        authorizedPersonName: _authorizedPersonController.text.trim(),
        farmName: _farmNameController.text.trim(),
        farmAddress: _farmAddressController.text.trim(),
        farmCell: _farmCellController.text.trim(),
        huntStartDate: _huntStartDate,
        huntEndDate: _huntEndDate,
        speciesHuntedAndTransported: _speciesList,
      );

      final permitId = await _permitManager.issueVenisonPermit(
        permit: permit,
        hunterSignatureBytes: hunterSig,
        outfitterSignatureBytes: outfitterSig,
      );

      if (mounted) {
        _showSuccessDialog(permitId);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to issue permit: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _showSuccessDialog(String permitId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Permit Issued',
                  style: TextStyle(color: widget.theme.textColor)),
            ),
          ],
        ),
        content: Text(
          'The legal SA venison transport & hunt permit has been issued and saved.\n\n'
          'Permit reference: $permitId',
          style: TextStyle(color: widget.theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // back to list / dashboard
            },
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: const Text('Venison Transport Permit',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      body: _isPrefilling
          ? Center(
              child: CircularProgressIndicator(color: theme.accentColor),
            )
          : Form(
              key: _formKey,
              child: ListView(
                // Bottom content inset reserves 90px so the signature +
                // transport fields clear the sticky ISSUE & SIGN PERMIT
                // button (which is itself wrapped in SafeArea(bottom: true)
                // to clear the Android 3-button / gesture nav bar). 90px
                // matches the sticky action bar's height + breathing room.
                padding: const EdgeInsets.only(
                  left: 16,
                  top: 16,
                  right: 16,
                  bottom: 90.0,
                ),
                children: [
                  _buildBrandedHeader(theme),
                  const SizedBox(height: 20),
                  _buildSectionTitle(theme, 'HUNTER DETAILS',
                      icon: Icons.person_rounded),
                  const SizedBox(height: 12),
                  _buildHunterFields(theme),
                  const SizedBox(height: 24),
                  _buildSectionTitle(theme, 'AUTHORIZED PERSON / FARM',
                      icon: Icons.agriculture_rounded),
                  const SizedBox(height: 12),
                  _buildFarmFields(theme),
                  const SizedBox(height: 24),
                  _buildSectionTitle(theme, 'HUNT WINDOW',
                      icon: Icons.date_range_rounded),
                  const SizedBox(height: 12),
                  _buildDateRow(theme),
                  const SizedBox(height: 24),
                  _buildSectionTitle(theme, 'SPECIES HUNTED AND TRANSPORTED',
                      icon: Icons.pets_rounded),
                  const SizedBox(height: 12),
                  _buildSpeciesSection(theme),
                  const SizedBox(height: 24),
                  _buildSignatureSection(
                    theme,
                    title: 'HUNTER SIGNATURE',
                    controller: _hunterSignatureController,
                  ),
                  const SizedBox(height: 20),
                  _buildSignatureSection(
                    theme,
                    title: 'AUTHORIZED PERSON (OUTFITTER) SIGNATURE',
                    controller: _outfitterSignatureController,
                  ),
                  const SizedBox(height: 28),
                  // Sticky ISSUE & SIGN PERMIT button — wrapped in
                  // SafeArea(bottom: true) so it clears the Android 3-button /
                  // gesture navigation bar on every device.
                  SafeArea(
                    top: false,
                    bottom: true,
                    child: _buildSubmitButton(theme),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  // ── UI builders ──────────────────────────────────────────────────────

  Widget _buildBrandedHeader(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.accentColor,
            theme.accentColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/app logo/logo1.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 56,
                height: 56,
                color: Colors.white,
                child: Icon(Icons.verified_user_rounded,
                    color: theme.accentColor, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JAGSPOOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Legal SA Venison / Game Transport & Hunt Permit',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeController theme, String label,
      {required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildHunterFields(ThemeController theme) {
    return _Card(
      theme: theme,
      child: Column(
        children: [
          _TextField(
            controller: _hunterNameController,
            label: 'Hunter Full Name',
            theme: theme,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _hunterIdController,
            label: 'ID / Passport Number',
            theme: theme,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _hunterCellController,
            label: 'Cell Phone Number',
            theme: theme,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _hunterAddressController,
            label: 'Residential Address',
            theme: theme,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildFarmFields(ThemeController theme) {
    return _Card(
      theme: theme,
      child: Column(
        children: [
          _TextField(
            controller: _authorizedPersonController,
            label: 'Authorized Person Name',
            theme: theme,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _farmNameController,
            label: 'Farm Name',
            theme: theme,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _farmAddressController,
            label: 'Farm Address',
            theme: theme,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          _TextField(
            controller: _farmCellController,
            label: 'Farm / Authorized Person Cell',
            theme: theme,
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  Widget _buildDateRow(ThemeController theme) {
    return _Card(
      theme: theme,
      child: Row(
        children: [
          Expanded(
            child: _DateField(
              label: 'Hunt Start Date',
              value: _huntStartDate,
              theme: theme,
              onTap: () => _pickDate(isStart: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DateField(
              label: 'Hunt End Date',
              value: _huntEndDate,
              theme: theme,
              onTap: () => _pickDate(isStart: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesSection(ThemeController theme) {
    return _Card(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_speciesList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No species added yet. Tap "Add Species" to declare species hunted and transported.',
                style: TextStyle(color: theme.subtitleColor, fontSize: 12),
              ),
            )
          else
            ..._speciesList.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pets_rounded,
                        color: theme.accentColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${s['species']} — ${s['quantity']}x ${s['sex'] ?? ''}',
                        style:
                            TextStyle(color: theme.textColor, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 20, color: Colors.red),
                      onPressed: () => _removeSpecies(i),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addSpecies,
              icon: Icon(Icons.add_rounded, color: theme.accentColor),
              label: Text('Add Species',
                  style: TextStyle(color: theme.accentColor)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignatureSection(
    ThemeController theme, {
    required String title,
    required SignatureController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.subtitleColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
                child: SizedBox(
                  height: 150,
                  child: Signature(
                    controller: controller,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(11),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sign above with your finger',
                      style: TextStyle(
                        color: theme.subtitleColor,
                        fontSize: 12,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => controller.clear(),
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(ThemeController theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitPermit,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: theme.accentColor.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.verified_rounded),
        label: Text(
          _isSubmitting ? 'ISSUING PERMIT…' : 'ISSUE & SIGN PERMIT',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }
}

// ── Reusable form widgets ─────────────────────────────────────────────

class _Card extends StatelessWidget {
  final ThemeController theme;
  final Widget child;

  const _Card({required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.15)),
      ),
      child: child,
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ThemeController theme;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;

  const _TextField({
    required this.controller,
    required this.label,
    required this.theme,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: theme.textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.subtitleColor),
        filled: true,
        fillColor: theme.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.accentColor, width: 1.5),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ThemeController theme;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: theme.subtitleColor, fontSize: 10)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.event_rounded,
                    color: theme.accentColor, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value != null
                        ? '${value!.day}/${value!.month}/${value!.year}'
                        : 'Select date',
                    style: TextStyle(
                      color: value != null ? theme.textColor : theme.subtitleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Multi-species add dialog — species name, sex, quantity.
class _AddSpeciesDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAdd;

  const _AddSpeciesDialog({required this.onAdd});

  @override
  State<_AddSpeciesDialog> createState() => _AddSpeciesDialogState();
}

class _AddSpeciesDialogState extends State<_AddSpeciesDialog> {
  final _speciesController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _selectedSex = 'Male';

  static const List<String> _sexOptions = ['Male', 'Female'];

  @override
  void dispose() {
    _speciesController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Species'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _speciesController,
            decoration: const InputDecoration(
              labelText: 'Species Name',
              hintText: 'e.g. Kudu, Impala, Springbok',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedSex,
            decoration: const InputDecoration(labelText: 'Sex'),
            items: _sexOptions
                .map((sex) => DropdownMenuItem(value: sex, child: Text(sex)))
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedSex = value ?? 'Male'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_speciesController.text.isEmpty) return;
            widget.onAdd({
              'species': _speciesController.text.trim(),
              'sex': _selectedSex,
              'quantity': int.tryParse(_quantityController.text) ?? 1,
            });
            Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
