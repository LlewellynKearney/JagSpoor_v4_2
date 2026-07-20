import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'AMMUNITION MANAGER',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _currentUserId != null
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
                      Icon(Icons.shield_outlined, size: 64, color: theme.subtitleColor),
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

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final make = data['make'] ?? 'Unknown';
                final model = data['model'] ?? 'Unknown';
                final caliber = data['caliber'] ?? 'N/A';

                return Card(
                  color: theme.cardColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    title: Text(
                      '$make $model',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.textColor,
                      ),
                    ),
                    subtitle: Text(
                      'Caliber: $caliber',
                      style: TextStyle(color: theme.subtitleColor),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, color: theme.accentColor, size: 18),
                    onTap: () {
                      final firearmEntity = <String, String>{
                        'docId': doc.id,
                        ...data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
                      };
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AmmunitionTypeSelectionScreen(
                            theme: theme,
                            firearm: firearmEntity,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
