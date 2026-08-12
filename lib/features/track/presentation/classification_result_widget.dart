import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/animal.dart';
import '../../../core/theme/app_theme.dart';
import '../data/track_taxonomy.dart';
import '../../hunter_mode/add_trophy_screen.dart';

class ClassificationResultWidget extends StatefulWidget {
  final String speciesName;
  final double confidence;
  final ThemeController theme;
  final String? gpsCoordinates;

  /// Optional ranked top-3 candidates. When supplied, all three matches are
  /// shown with confidence bars instead of a single absolute result.
  final List<SpoorPrediction>? topPredictions;

  /// Optional morphological category used for the scan; drives the anatomical
  /// verification prompts shown beneath the predictions.
  final TrackCategory? category;

  const ClassificationResultWidget({
    super.key,
    required this.speciesName,
    required this.confidence,
    required this.theme,
    this.gpsCoordinates,
    this.topPredictions,
    this.category,
  });

  @override
  State<ClassificationResultWidget> createState() =>
      _ClassificationResultWidgetState();
}

class _ClassificationResultWidgetState
    extends State<ClassificationResultWidget> {
  String? _selectedFirearmId;
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  Future<Animal?> _resolveAnimal() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('animals').get();
      for (final doc in snapshot.docs) {
        final animal = Animal.fromFirestore(doc);
        if (animal.name.toLowerCase() == widget.speciesName.toLowerCase()) {
          return animal;
        }
      }
    } catch (e) {
      debugPrint('Error resolving animal: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final confidencePercent = (widget.confidence * 100).toStringAsFixed(1);
    final isLowConfidence = widget.confidence < 0.5;
    final top = widget.topPredictions ?? const <SpoorPrediction>[];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.theme.accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isLowConfidence
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                color:
                    isLowConfidence ? Colors.orange : widget.theme.accentColor,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.speciesName,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: widget.theme.textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AI Confidence: $confidencePercent%',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isLowConfidence
                                ? Colors.orange
                                : widget.theme.subtitleColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.confidence,
              minHeight: 8,
              backgroundColor: widget.theme.accentColor.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isLowConfidence ? Colors.orange : widget.theme.accentColor,
              ),
            ),
          ),

          // Top-3 candidate matches.
          if (top.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'TOP MATCHES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.theme.subtitleColor,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < top.length; i++)
              _buildPredictionRow(top[i], i == 0),
          ],

          // Anatomical verification prompts (only when a category was chosen).
          if (widget.category != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.theme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.theme.accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.fact_check_outlined,
                        size: 18,
                        color: widget.theme.accentColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verify anatomical features (${categoryLabel(widget.category!)})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: widget.theme.textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final prompt in verificationPrompts(widget.category!))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_box_outline_blank,
                            size: 18,
                            color: widget.theme.subtitleColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              prompt,
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.theme.subtitleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          Text(
            'Associate Firearm',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: widget.theme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream:
                _currentUserId != null
                    ? FirebaseFirestore.instance
                        .collection('firearms')
                        .where('ownerId', isEqualTo: _currentUserId)
                        .orderBy('createdAt', descending: true)
                        .snapshots()
                    : const Stream.empty(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Error loading firearms',
                  style: TextStyle(color: widget.theme.subtitleColor),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(
                  'No firearms found. Create one in the Firearm Safe first.',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.theme.subtitleColor,
                    fontStyle: FontStyle.italic,
                  ),
                );
              }

              return DropdownButtonFormField<String>(
                value: _selectedFirearmId,
                dropdownColor: widget.theme.backgroundColor,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.theme.accentColor.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: widget.theme.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.theme.accentColor),
                  ),
                ),
                hint: Text(
                  'Select firearm used',
                  style: TextStyle(
                    color: widget.theme.subtitleColor,
                    fontSize: 14,
                  ),
                ),
                onChanged: (val) => setState(() => _selectedFirearmId = val),
                items:
                    docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final make = data['make'] ?? 'Unknown';
                      final caliber = data['caliber'] ?? 'N/A';
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(
                          '$make ($caliber)',
                          style: TextStyle(
                            color: widget.theme.textColor,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder:
                    (context) =>
                        const Center(child: CircularProgressIndicator()),
              );

              final animal = await _resolveAnimal();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => AddTrophyScreen(
                          theme: widget.theme,
                          initialAnimal: animal,
                          initialGpsCoordinates: widget.gpsCoordinates,
                          initialFirearmId: _selectedFirearmId,
                        ),
                  ),
                );
              }
            },
            icon: Icon(
              Icons.emoji_events_rounded,
              color: widget.theme.backgroundColor,
            ),
            label: Text(
              'Log to Trophy Room',
              style: TextStyle(
                color: widget.theme.backgroundColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.theme.accentColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionRow(SpoorPrediction p, bool isTop) {
    final pct = p.confidencePercent.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            isTop ? Icons.military_tech_rounded : Icons.label_outline,
            size: 18,
            color: isTop ? widget.theme.accentColor : widget.theme.subtitleColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.species,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                color:
                    isTop ? widget.theme.textColor : widget.theme.subtitleColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              '$pct%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isTop ? widget.theme.accentColor : widget.theme.subtitleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
