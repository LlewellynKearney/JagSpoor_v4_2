import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// ScopeToolsBottomSheet provides a modal interface for configuring
/// rifle scope settings including reticle type, adjustment values,
/// and environmental compensation factors.
class ScopeToolsBottomSheet extends StatefulWidget {
  const ScopeToolsBottomSheet({super.key});

  @override
  State<ScopeToolsBottomSheet> createState() => _ScopeToolsBottomSheetState();
}

class _ScopeToolsBottomSheetState extends State<ScopeToolsBottomSheet> {
  // Scope reticle type selection
  String _selectedReticle = 'Mil-Dot';
  static const List<String> _reticleTypes = [
    'Mil-Dot',
    'MOA',
    'BDC (Bullet Drop Compensator)',
    'German #4',
    'Ballistic Plex',
    'Tactical Milling',
  ];

  // Scope adjustment settings
  double _clickValue = 0.25; // MOA per click
  double _tubeDiameter = 30.0; // mm
  double _objectiveDiameter = 50.0; // mm

  // Turret settings
  double _elevationAdjustment = 0.0; // MOA
  double _windageAdjustment = 0.0; // MOA

  // Parallax settings
  double _parallaxDistance = 100.0; // yards

  // Illumination settings
  bool _isIlluminated = false;
  double _illuminationLevel = 5.0;

  // Calculate scope resolution factor
  double _calculateResolutionFactor() {
    return (_tubeDiameter / 25.4) * sqrt(_objectiveDiameter / 50.0);
  }

  // Calculate reticle group size based on settings
  double _calculateReticleGroupSize() {
    const double baseSize = 2.0; // MOA
    final resolutionFactor = _calculateResolutionFactor();
    return baseSize / resolutionFactor;
  }

  // Calculate effective range based on parallax
  double _calculateEffectiveRange() {
    // Simplified calculation: parallax setting affects effective range
    return (_parallaxDistance / 100) * 500; // yards
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: const Color(0xFFC5A059).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.center_focus_strong,
                    color: Color(0xFFC5A059),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '🎯 SCOPE SETTINGS & TOOLS',
                      style: TextStyle(
                        color: Color(0xFFC5A059),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Reticle Type Selection
              _buildSectionHeader('Reticle Configuration'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFC5A059).withValues(alpha: 0.2),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedReticle,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: _reticleTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (!context.mounted) return;
                      setState(() => _selectedReticle = value!);
                    },
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Scope Dimensions
              _buildSectionHeader('Scope Dimensions'),
              const SizedBox(height: 8),
              _buildSliderTile(
                label: 'Tube Diameter',
                value: _tubeDiameter,
                unit: 'mm',
                min: 25.0,
                max: 40.0,
                onChanged: (v) => setState(() => _tubeDiameter = v),
              ),
              _buildSliderTile(
                label: 'Objective Diameter',
                value: _objectiveDiameter,
                unit: 'mm',
                min: 40.0,
                max: 60.0,
                onChanged: (v) => setState(() => _objectiveDiameter = v),
              ),

              const SizedBox(height: 20),

              // Click Value Settings
              _buildSectionHeader('Adjustment Settings'),
              const SizedBox(height: 8),
              _buildSliderTile(
                label: 'Click Value',
                value: _clickValue,
                unit: 'MOA',
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: (v) => setState(() => _clickValue = v),
              ),

              const SizedBox(height: 20),

              // Turret Adjustments
              _buildSectionHeader('Turret Adjustments'),
              const SizedBox(height: 8),
              _buildSliderTile(
                label: 'Elevation',
                value: _elevationAdjustment,
                unit: 'MOA',
                min: -20.0,
                max: 20.0,
                onChanged: (v) => setState(() => _elevationAdjustment = v),
              ),
              _buildSliderTile(
                label: 'Windage',
                value: _windageAdjustment,
                unit: 'MOA',
                min: -20.0,
                max: 20.0,
                onChanged: (v) => setState(() => _windageAdjustment = v),
              ),

              const SizedBox(height: 20),

              // Parallax Settings
              _buildSectionHeader('Parallax Correction'),
              const SizedBox(height: 8),
              _buildSliderTile(
                label: 'Parallax Distance',
                value: _parallaxDistance,
                unit: 'yd',
                min: 50.0,
                max: 300.0,
                divisions: 25,
                onChanged: (v) => setState(() => _parallaxDistance = v),
              ),

              const SizedBox(height: 20),

              // Illumination Settings
              _buildSectionHeader('Illumination'),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text(
                  'Illuminated Reticle',
                  style: TextStyle(color: Colors.white),
                ),
                value: _isIlluminated,
                activeColor: const Color(0xFFC5A059),
                onChanged: (v) {
                  if (!context.mounted) return;
                  setState(() => _isIlluminated = v);
                },
              ),
              if (_isIlluminated)
                _buildSliderTile(
                  label: 'Brightness Level',
                  value: _illuminationLevel,
                  unit: '',
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  onChanged: (v) => setState(() => _illuminationLevel = v),
                ),

              const SizedBox(height: 24),

              // Calculated Values Display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFC5A059).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CALCULATED VALUES',
                      style: TextStyle(
                        color: Color(0xFFC5A059),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildCalcRow(
                      'Resolution Factor',
                      _calculateResolutionFactor().toStringAsFixed(3),
                    ),
                    _buildCalcRow(
                      'Reticle Group Size',
                      '${_calculateReticleGroupSize().toStringAsFixed(3)} MOA',
                    ),
                    _buildCalcRow(
                      'Effective Range',
                      '${_calculateEffectiveRange().toStringAsFixed(0)} yards',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFC5A059)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC5A059),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        if (!context.mounted) return;
                        _saveScopeSettings();
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'APPLY SETTINGS',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFFC5A059),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSliderTile({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: const Color(0xFFC5A059),
              inactiveColor: Colors.grey.withValues(alpha: 0.3),
              onChanged: (v) {
                if (!context.mounted) return;
                onChanged(v);
              },
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                color: Color(0xFFC5A059),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalcRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFC5A059),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _saveScopeSettings() {
    // Save scope settings to local preferences
    // This would integrate with shared_preferences or a dedicated settings service
    debugPrint('Scope settings saved:');
    debugPrint('  Reticle: $_selectedReticle');
    debugPrint('  Click Value: $_clickValue MOA');
    debugPrint('  Tube: $_tubeDiameter mm');
    debugPrint('  Objective: $_objectiveDiameter mm');
    debugPrint('  Elevation: $_elevationAdjustment MOA');
    debugPrint('  Windage: $_windageAdjustment MOA');
    debugPrint('  Parallax: $_parallaxDistance yd');
    debugPrint('  Illuminated: $_isIlluminated');
  }
}
