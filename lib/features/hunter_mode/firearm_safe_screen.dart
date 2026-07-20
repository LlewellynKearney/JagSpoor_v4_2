import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import 'add_firearm_manual_form.dart';
import 'firearm_detail_screen.dart';
import 'firearm_maintenance_screen.dart';
import 'maintenance.dart';
import '../firearm_safe/data/services/firearm_pdf_generator.dart';

class FirearmSafeScreen extends StatefulWidget {
  final ThemeController theme;
  const FirearmSafeScreen({super.key, required this.theme});

  @override
  State<FirearmSafeScreen> createState() => _FirearmSafeScreenState();
}

class _FirearmSafeScreenState extends State<FirearmSafeScreen> {
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _logRounds(Map<String, String> firearm) async {
    final added = await showAddRoundsDialog(context, widget.theme);
    if (added == null || !mounted) return;
    final docId = firearm['docId'];
    if (docId != null) {
      final updatedFirearm = <String, String>{...firearm};
      recordRounds(updatedFirearm, added);
      await FirebaseFirestore.instance
          .collection('firearms')
          .doc(docId)
          .update(updatedFirearm);
    }
  }

  void _openMaintenance(Map<String, String> firearm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FirearmMaintenanceScreen(
          theme: widget.theme,
          firearm: firearm,
          onLogAdded: (record) async {
            final docId = firearm['docId'];
            if (docId != null) {
              final log = parseLog(firearm)..add(record);
              final updatedFirearm = <String, String>{...firearm};
              updatedFirearm['maintenanceLog'] = encodeLog(log);
              await FirebaseFirestore.instance
                  .collection('firearms')
                  .doc(docId)
                  .update(updatedFirearm);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        title: Text(
          'DIGITAL FIREARM SAFE',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: theme.backgroundColor,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: theme.accentColor),
            tooltip: 'Export PDF',
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final snapshot = await FirebaseFirestore.instance
                  .collection('firearms')
                  .where('ownerId', isEqualTo: _currentUserId)
                  .orderBy('createdAt', descending: true)
                  .get();
              if (!mounted) return;
              final firearms = snapshot.docs.map((doc) {
                final data = doc.data();
                return <String, String>{
                  'docId': doc.id,
                  ...data.map(
                    (key, value) => MapEntry(key, value?.toString() ?? ''),
                  ),
                };
              }).toList();
              if (firearms.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'No firearms to export. Add firearms to your digital safe first.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              await FirearmPdfGenerator.generateAndShowFirearmsPdf(firearms);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildVaultStatusCard(theme),
              const SizedBox(height: 24),
              Text(
                'REGISTERED ARSENAL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.subtitleColor,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
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
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Unable to load firearms.\n${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.subtitleColor),
                          ),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.accentColor,
                          ),
                        ),
                      );
                    }

                    final firearms = snapshot.data?.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return <String, String>{
                        'docId': doc.id,
                        ...data.map(
                          (key, value) =>
                              MapEntry(key, value?.toString() ?? ''),
                        ),
                      };
                    }).toList();

                    if (firearms == null || firearms.isEmpty) {
                      return _buildEmptyState(theme);
                    }

                    return ListView.builder(
                      itemCount: firearms.length,
                      itemBuilder: (context, index) {
                        final firearm = firearms[index];
                        return _buildFirearmCard(theme, firearm, index);
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Icon(
                            Icons.qr_code_scanner_rounded,
                            color: theme.isDarkMode
                                ? Colors.black
                                : Colors.white,
                          ),
                          label: Text(
                            'SCAN LICENSE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.isDarkMode
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                          onPressed: () async {
                            final Map<String, String>? newFirearm =
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddFirearmManualForm(
                                      theme: theme,
                                      autoScan: true,
                                    ),
                                  ),
                                );

                            if (newFirearm != null && mounted) {
                              final ownerId =
                                  _currentUserId ??
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (ownerId != null) {
                                final docRef = await FirebaseFirestore.instance
                                    .collection('firearms')
                                    .add({
                                      ...newFirearm,
                                      'ownerId': ownerId,
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                newFirearm['docId'] = docRef.id;
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: theme.accentColor,
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: Icon(
                            Icons.add_rounded,
                            color: theme.accentColor,
                          ),
                          label: Text(
                            'ADD MANUALLY',
                            style: TextStyle(
                              color: theme.accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            final Map<String, String>? newFirearm =
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddFirearmManualForm(theme: theme),
                                  ),
                                );

                            if (newFirearm != null && mounted) {
                              final ownerId =
                                  _currentUserId ??
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (ownerId != null) {
                                final docRef = await FirebaseFirestore.instance
                                    .collection('firearms')
                                    .add({
                                      ...newFirearm,
                                      'ownerId': ownerId,
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });
                                newFirearm['docId'] = docRef.id;
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFirearmCard(
    ThemeController theme,
    Map<String, String> firearm,
    int index,
  ) {
    final total = barrelLifeTotal(firearm);
    final remaining = barrelLifeRemaining(firearm);
    final usedFraction = barrelLifeUsedFraction(firearm);
    final usedPct = barrelLifeUsedPercent(firearm);
    final validity = licenceValidity(firearm['expiry']);
    final expired = validity == 'Expired';

    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FirearmDetailScreen(
              theme: theme,
              firearm: firearm,
              onUpdated: (updated) async {
                final docId = firearm['docId'];
                if (docId != null) {
                  await FirebaseFirestore.instance
                      .collection('firearms')
                      .doc(docId)
                      .update(updated);
                }
              },
              onDeleted: () async {
                final docId = firearm['docId'];
                if (docId != null) {
                  await FirebaseFirestore.instance
                      .collection('firearms')
                      .doc(docId)
                      .delete();
                }
              },
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, color: theme.accentColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${firearm['make']} (${firearm['caliber']})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'S/N: ${firearm['serial']}',
                          style: TextStyle(
                            color: theme.subtitleColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.build_rounded,
                      color: isMaintenanceDue(firearm)
                          ? Colors.red
                          : theme.subtitleColor,
                    ),
                    tooltip: 'Maintenance',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openMaintenance(firearm),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: theme.subtitleColor,
                    size: 14,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    expired
                        ? Icons.event_busy_rounded
                        : Icons.verified_user_rounded,
                    size: 15,
                    color: expired ? Colors.red : theme.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Licence: $validity',
                    style: TextStyle(
                      fontSize: 13,
                      color: expired ? Colors.red : theme.textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (total > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Barrel life: $remaining rds left',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$usedPct% used',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: usedPct >= 85 ? Colors.red : theme.accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: usedFraction,
                    minHeight: 8,
                    backgroundColor: theme.subtitleColor.withValues(alpha: 0.2),
                    color: usedPct >= 85 ? Colors.red : theme.accentColor,
                  ),
                ),
              ] else
                Text(
                  'Barrel life: not set',
                  style: TextStyle(fontSize: 13, color: theme.subtitleColor),
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _logRounds(firearm),
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: theme.accentColor,
                  ),
                  label: Text(
                    'LOG ROUNDS',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultStatusCard(ThemeController theme) {
    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.accentColor.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.gpp_good_rounded, color: theme.accentColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VAULT SECURITY: ACTIVE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Local database encrypted. Registry state live.',
                    style: TextStyle(color: theme.subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeController theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_open_rounded, size: 64, color: theme.subtitleColor),
          const SizedBox(height: 16),
          Text(
            'No Registered Firearms Found',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
