import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../hunter_mode/widgets/hunter_scaffold.dart';
import '../../shared/widgets/hunter_grid_container.dart';
import '../../shared/widgets/hunter_media_card.dart';
import 'ammunition_type_selection_screen.dart';

class AmmunitionScreen extends StatefulWidget {
  final ThemeController theme;
  const AmmunitionScreen({super.key, required this.theme});

  @override
  State<AmmunitionScreen> createState() => _AmmunitionScreenState();
}

class _AmmunitionScreenState extends State<AmmunitionScreen> {
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return HunterScaffold(
      theme: theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Text(
          'AMMUNITION MANAGER',
          style: TextStyle(
            color: HunterUi.titleColor(theme),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: HunterUi.titleColor(theme)),
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
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
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text(
                    'Error loading firearms',
                    style: TextStyle(color: theme.subtitleColor),
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: theme.accentColor),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 64,
                        color: theme.subtitleColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'NO FIREARMS IN SAFE',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please register a firearm in the digital safe first.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.subtitleColor),
                      ),
                    ],
                  ),
                ),
              );
            }

            return HunterGridContainer(
              padding: const EdgeInsets.all(16),
              maxCrossAxisExtent: 260,
              childAspectRatio: 1.3,
              spacing: 12,
              children: [
                for (final doc in docs) _buildFirearmAmmoCard(theme, doc),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Rich-media ammunition profile card for a registered firearm: full-bleed
  /// tactical photo (or the dark placeholder) with a frosted amber caliber
  /// data pill across the lower section.
  Widget _buildFirearmAmmoCard(
    ThemeController theme,
    QueryDocumentSnapshot doc,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final make = (data['make'] as String?) ?? 'Unknown';
    final model = (data['model'] as String?) ?? 'Unknown';
    final caliber = (data['caliber'] as String?) ?? 'N/A';
    final photoPath = (data['photoPath'] as String?)?.trim() ?? '';

    return HunterMediaCard(
      theme: theme,
      image: photoPath.isNotEmpty ? NetworkImage(photoPath) : null,
      fallbackIcon: Icons.shield_rounded,
      title: '$make $model',
      topLeftPill: const HunterMediaPill(
        icon: Icons.inventory_2_rounded,
        label: 'AMMUNITION PROFILE',
        amber: true,
      ),
      pills: [
        HunterMediaPill(icon: Icons.gps_fixed_rounded, label: caliber, amber: true),
      ],
      onTap: () {
        final firearmEntity = <String, String>{
          'docId': doc.id,
          ...data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
        };
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => AmmunitionTypeSelectionScreen(
                  theme: theme,
                  firearm: firearmEntity,
                ),
          ),
        );
      },
    );
  }
}
