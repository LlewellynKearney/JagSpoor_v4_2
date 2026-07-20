import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AddFirearmManualForm extends StatefulWidget {
  final ThemeController theme;

  /// When true, the licence scanner is launched automatically on open so the
  /// form opens pre-filled (used by the safe's "SCAN LICENSE" action).
  final bool autoScan;

  /// Existing firearm data to edit; when provided the form opens pre-filled.
  final Map<String, String>? initial;

  const AddFirearmManualForm({
    super.key,
    required this.theme,
    this.autoScan = false,
    this.initial,
  });

  @override
  State<AddFirearmManualForm> createState() => _AddFirearmManualFormState();
}

class _AddFirearmManualFormState extends State<AddFirearmManualForm> {
  final _formKey = GlobalKey<FormState>();

  // Licence holder
  final _licenceType = TextEditingController();
  final _holderName = TextEditingController();
  final _idNumber = TextEditingController();

  // Firearm details (scanned)
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _caliber = TextEditingController();
  final _serial = TextEditingController();
  final _licenceNumber = TextEditingController();
  final _licenceSection = TextEditingController();
  final _firearmType = TextEditingController();
  final _manufacturer = TextEditingController();
  final _issueDate = TextEditingController();
  final _expiryDate = TextEditingController();

  // Manual-only (not present in the barcode)
  final _barrelLength = TextEditingController();
  final _barrelLife = TextEditingController();
  final _twistRate = TextEditingController();
  final _actionType = TextEditingController();

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _licenceType.text = init['licenceType'] ?? '';
      _holderName.text = init['holderName'] ?? '';
      _idNumber.text = init['idNumber'] ?? '';
      _make.text = init['make'] ?? '';
      _model.text = init['model'] ?? '';
      _caliber.text = init['caliber'] ?? '';
      _serial.text = init['serial'] ?? '';
      _licenceNumber.text = init['licenceNumber'] ?? '';
      _licenceSection.text = init['licenceSection'] ?? '';
      _firearmType.text = init['firearmType'] ?? '';
      _manufacturer.text = init['manufacturer'] ?? '';
      _issueDate.text = init['issueDate'] ?? '';
      final exp = init['expiry'] ?? '';
      _expiryDate.text = exp == 'N/A' ? '' : exp;
      _barrelLength.text = init['barrelLength'] ?? '';
      _barrelLife.text = init['barrelLife'] ?? '';
      _twistRate.text = init['twistRate'] ?? '';
      _actionType.text = init['actionType'] ?? '';
    }
    if (widget.autoScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchScanner());
    }
  }

  @override
  void dispose() {
    for (final c in [
      _licenceType, _holderName, _idNumber, _make, _model, _caliber, _serial,
      _licenceNumber, _licenceSection, _firearmType, _manufacturer, _issueDate,
      _expiryDate, _barrelLength, _barrelLife, _twistRate, _actionType,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _launchScanner() async {
    final result = await Navigator.pushNamed(context, '/scan_license');
    if (!mounted || result is! Map) return;
    final r = Map<String, dynamic>.from(result);
    String s(String key) => (r[key] is String) ? r[key] as String : '';
    setState(() {
      _licenceType.text = s('licenceType');
      _holderName.text = s('holderName');
      _idNumber.text = s('idNumber');
      _make.text = s('make');
      _model.text = s('model');
      _caliber.text = s('caliber');
      _serial.text = s('serial');
      _licenceNumber.text = s('licenseNumber');
      _licenceSection.text = s('licenceSection');
      _firearmType.text = s('firearmType');
      _manufacturer.text = s('manufacturer');
      _issueDate.text = s('issueDate');
      _expiryDate.text = s('expiryDate');
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().split('T').first;
    }
  }

  // Luhn checksum validation for a South African ID number.
  bool _isValidRsaId(String value) {
    if (!RegExp(r'^[0-9]{13}$').hasMatch(value)) return false;
    int sum = 0;
    bool alternate = false;
    for (int i = value.length - 2; i >= 0; i--) {
      int digit = int.parse(value[i]);
      if (alternate) {
        digit *= 2;
        if (digit > 9) digit = (digit % 10) + 1;
      }
      sum += digit;
      alternate = !alternate;
    }
    final checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(value[value.length - 1]);
  }

  void _saveFirearm() {
    if (!_formKey.currentState!.validate()) return;
    final firearmData = <String, String>{
      'licenceType': _licenceType.text.trim(),
      'holderName': _holderName.text.trim(),
      'idNumber': _idNumber.text.trim(),
      'make': _make.text.trim(),
      'model': _model.text.trim(),
      'caliber': _caliber.text.trim(),
      'serial': _serial.text.trim(),
      'licenceNumber': _licenceNumber.text.trim(),
      'licenceSection': _licenceSection.text.trim(),
      'firearmType': _firearmType.text.trim(),
      'manufacturer': _manufacturer.text.trim(),
      'issueDate': _issueDate.text.trim(),
      'expiry': _expiryDate.text.trim().isEmpty ? 'N/A' : _expiryDate.text.trim(),
      'barrelLength': _barrelLength.text.trim(),
      'barrelLife': _barrelLife.text.trim(),
      'twistRate': _twistRate.text.trim(),
      'actionType': _actionType.text.trim(),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Firearm saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.pop(context, firearmData);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(widget.initial != null ? 'EDIT FIREARM' : 'FIREARM REGISTRY',
            style: TextStyle(color: theme.textColor)),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _launchScanner,
            tooltip: 'Scan licence card',
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20.0),
            children: [
              _section(theme, 'LICENCE HOLDER'),
              _field(theme, _licenceType, 'Licence Type'),
              _field(theme, _holderName, 'Holder Name'),
              _field(
                theme,
                _idNumber,
                'ID Number',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  return _isValidRsaId(v) ? null : 'Invalid South African ID format';
                },
              ),
              _section(theme, 'FIREARM DETAILS'),
              _field(theme, _make, 'Make',
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Please enter the make' : null),
              _field(theme, _model, 'Model'),
              _field(theme, _caliber, 'Caliber'),
              _field(theme, _serial, 'Serial Number',
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Please enter the serial number'
                      : null),
              _field(theme, _licenceNumber, 'License Number'),
              _field(theme, _licenceSection, 'License Section'),
              _field(theme, _firearmType, 'Firearm Type'),
              _field(theme, _manufacturer, 'Manufacturer / Importer'),
              _dateField(theme, _issueDate, 'Issue Date'),
              _dateField(theme, _expiryDate, 'Expiry Date'),
              _section(theme, 'SPECIFICATIONS (MANUAL)'),
              _field(theme, _barrelLength, 'Barrel Length'),
              _field(theme, _barrelLife, 'Barrel Life'),
              _field(theme, _twistRate, 'Twist Rate'),
              _field(theme, _actionType, 'Action Type'),
              const SizedBox(height: 16.0),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  side: BorderSide(color: theme.accentColor, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                ),
                icon: Icon(Icons.qr_code_scanner, color: theme.accentColor),
                label: Text('SCAN LICENSE',
                    style: TextStyle(
                        color: theme.accentColor, fontWeight: FontWeight.bold)),
                onPressed: _launchScanner,
              ),
              const SizedBox(height: 12.0),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                ),
                onPressed: _saveFirearm,
                child: Text('SAVE FIREARM',
                    style: TextStyle(
                        color: theme.isDarkMode ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(ThemeController theme, String label) => Padding(
        padding: const EdgeInsets.only(top: 8.0, bottom: 12.0),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.subtitleColor,
                letterSpacing: 1.5)),
      );

  Widget _field(
    ThemeController theme,
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: TextStyle(color: theme.textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.subtitleColor),
          fillColor: theme.cardColor,
          filled: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
        validator: validator,
      ),
    );
  }

  Widget _dateField(
      ThemeController theme, TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        onTap: () => _pickDate(controller),
        style: TextStyle(color: theme.textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: theme.subtitleColor),
          fillColor: theme.cardColor,
          filled: true,
          suffixIcon: Icon(Icons.calendar_today, color: theme.accentColor),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
        ),
      ),
    );
  }
}
