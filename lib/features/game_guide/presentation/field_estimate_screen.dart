import 'package:flutter/material.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/utils/animal_seeder.dart';

class FieldEstimateScreen extends StatefulWidget {
  final ThemeController theme;

  const FieldEstimateScreen({super.key, required this.theme});

  @override
  State<FieldEstimateScreen> createState() => _FieldEstimateScreenState();
}

class _FieldEstimateScreenState extends State<FieldEstimateScreen> {
  late final List<String> _species;
  String? _selectedSpecies;
  double _multiplier = 1.0;

  @override
  void initState() {
    super.initState();
    _species = getRolandWardSpeciesNames();
    _selectedSpecies = _species.isNotEmpty ? _species.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _selectedSpecies == null
        ? null
        : getRolandWardMetricsForSpecies(_selectedSpecies!);
    final earLength = metrics?.earLength;
    final minimumValue = _parseRolandWardMinimum(metrics?.rwMinimum);
    final estimatedHornLength = earLength == null ? null : earLength * _multiplier;
    final isComparable = estimatedHornLength != null && minimumValue != null;
    bool? meetsMinimum;
    final comparableHornLength = estimatedHornLength;
    final comparableMinimumValue = minimumValue;
    if (comparableHornLength != null && comparableMinimumValue != null) {
      meetsMinimum = comparableHornLength >= comparableMinimumValue;
    }

    return Scaffold(
      backgroundColor: widget.theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'Field Estimate Verification',
          style: TextStyle(
            color: widget.theme.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: widget.theme.backgroundColor,
        iconTheme: IconThemeData(color: widget.theme.accentColor),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 16),
              _buildSelectorCard(metrics),
              const SizedBox(height: 16),
              _buildReferenceCard(metrics),
              const SizedBox(height: 16),
              _buildMultiplierCard(),
              const SizedBox(height: 16),
              _buildResultCard(
                estimatedHornLength: estimatedHornLength,
                minimumValue: minimumValue,
                meetsMinimum: meetsMinimum,
                isComparable: isComparable,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.remove_red_eye_rounded,
                  color: widget.theme.accentColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ear-to-Horn Visual Estimate',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: widget.theme.textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use the visible ear length as a reference and compare the resulting horn estimate against the Roland Ward minimum.',
              style: TextStyle(
                fontSize: 14,
                color: widget.theme.subtitleColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorCard(RolandWardMetrics? metrics) {
    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected Species',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSpecies,
              decoration: InputDecoration(
                labelText: 'Species',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: widget.theme.accentColor),
                ),
                filled: true,
                fillColor: widget.theme.backgroundColor.withValues(alpha: 0.55),
              ),
              items: _species
                  .map(
                    (species) => DropdownMenuItem<String>(
                      value: species,
                      child: Text(
                        species,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedSpecies = value);
                }
              },
            ),
            const SizedBox(height: 12),
            if (metrics != null)
              Text(
                'Reference data loaded for ${metrics.rwMinimum}.',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.theme.subtitleColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceCard(RolandWardMetrics? metrics) {
    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reference Benchmarks',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            if (metrics == null)
              Text(
                'Select a species to view its reference values.',
                style: TextStyle(color: widget.theme.subtitleColor),
              )
            else if (metrics.earLength == null)
              Text(
                'Visual ratio estimation not applicable for this species.',
                style: TextStyle(
                  color: widget.theme.accentColor,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Column(
                children: [
                  _infoRow(
                    title: 'Roland Ward minimum',
                    value: metrics.rwMinimum,
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    title: 'Baseline ear length',
                    value: '${metrics.earLength!.toStringAsFixed(2)} in',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiplierCard() {
    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visual Ratio Multiplier',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adjust the apparent horn-to-ear ratio captured through the optic.',
              style: TextStyle(
                fontSize: 13,
                color: widget.theme.subtitleColor,
              ),
            ),
            const SizedBox(height: 16),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: widget.theme.accentColor,
                inactiveTrackColor: widget.theme.accentColor.withValues(alpha: 0.2),
                thumbColor: widget.theme.accentColor,
                overlayColor: widget.theme.accentColor.withValues(alpha: 0.12),
              ),
              child: Slider(
                value: _multiplier,
                min: 0.5,
                max: 5.0,
                divisions: 18,
                label: _multiplier.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() => _multiplier = value);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0.50x', style: TextStyle(color: widget.theme.subtitleColor)),
                Text(
                  '${_multiplier.toStringAsFixed(2)}x',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.theme.textColor,
                  ),
                ),
                Text('5.00x', style: TextStyle(color: widget.theme.subtitleColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard({
    required double? estimatedHornLength,
    required double? minimumValue,
    required bool? meetsMinimum,
    required bool isComparable,
  }) {
    Color accentColor;
    String summary;

    if (estimatedHornLength == null) {
      accentColor = widget.theme.accentColor.withValues(alpha: 0.55);
      summary = 'No reference ear length is available for this species.';
    } else if (!isComparable || minimumValue == null) {
      accentColor = widget.theme.accentColor;
      summary = 'The Roland Ward minimum could not be compared numerically.';
    } else if (meetsMinimum == true) {
      accentColor = const Color(0xFF2E7D32);
      summary = 'Meets or exceeds the official Roland Ward minimum.';
    } else {
      accentColor = const Color(0xFFC62828);
      summary = 'Falls below the official Roland Ward minimum.';
    }

    return Card(
      color: widget.theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          color: accentColor.withValues(alpha: 0.08),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estimated Horn Length',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: widget.theme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              estimatedHornLength == null
                  ? 'Not applicable'
                  : '${estimatedHornLength.toStringAsFixed(2)} in',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                fontSize: 13,
                color: widget.theme.textColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.theme.backgroundColor.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: widget.theme.subtitleColor,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: widget.theme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  double? _parseRolandWardMinimum(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final numericValue = value.replaceAll(RegExp(r'[^0-9.]'), '');
    if (numericValue.isEmpty) {
      return null;
    }

    return double.tryParse(numericValue);
  }
}
