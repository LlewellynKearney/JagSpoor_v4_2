import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'add_firearm_manual_form.dart';
import 'firearm_detail_screen.dart';
import 'firearm_maintenance_screen.dart';
import 'maintenance.dart';
import '../firearm_safe/data/services/firearm_pdf_generator.dart';
import 'screens/firearm_renewal_screen.dart';
import 'package:jagspoor/features/hunter_mode/widgets/hunter_scaffold.dart';
import 'package:jagspoor/features/shared/widgets/hunter_grid_container.dart';
import 'package:jagspoor/features/shared/widgets/hunter_media_card.dart';
import 'package:jagspoor/shared/widgets/app_info_modal.dart';

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
        builder:
            (context) => FirearmMaintenanceScreen(
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

    return HunterScaffold(
      theme: widget.theme,
      padBodyForAppBar: true,
      appBar: AppBar(
        title: Text(
          'DIGITAL FIREARM SAFE',
          style: TextStyle(
            color: theme.textColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: HunterUi.titleColor(widget.theme)),
        elevation: 0,
        actions: [
          AppInfoIconButton(
            screenKey: AppScreenHelpScripts.hunterFirearmSafe,
            iconColor: theme.accentColor,
          ),
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: theme.accentColor),
            tooltip: 'Export PDF',
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final snapshot =
                  await FirebaseFirestore.instance
                      .collection('firearms')
                      .where('ownerId', isEqualTo: _currentUserId)
                      .orderBy('createdAt', descending: true)
                      .get();
              if (!mounted) return;
              final firearms =
                  snapshot.docs.map((doc) {
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

                    final firearms =
                        snapshot.data?.docs.map((doc) {
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

                    return HunterGridContainer(
                      padding: EdgeInsets.zero,
                      maxCrossAxisExtent: 340,
                      childAspectRatio: 1.0,
                      spacing: 14,
                      children: [
                        for (var i = 0; i < firearms.length; i++)
                          _buildFirearmCard(theme, firearms[i], i),
                      ],
                    );
                  },
                ),
              ),
              const CopyrightFooter(),
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
                            color:
                                theme.isDarkMode ? Colors.black : Colors.white,
                          ),
                          label: Text(
                            'SCAN LICENSE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  theme.isDarkMode
                                      ? Colors.black
                                      : Colors.white,
                            ),
                          ),
                          onPressed: () async {
                            final Map<String, String>? newFirearm =
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (context) => AddFirearmManualForm(
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
                                    builder:
                                        (context) =>
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

  /// Rich-media firearm card: a full-bleed tactical photo (or the dark
  /// tactical placeholder) with the licence status badge pill top-left,
  /// frosted quick-action circles top-right (log rounds / maintenance /
  /// renew licence), and frosted telemetry pills for the caliber + barrel
  /// life profile across the lower section.
  Widget _buildFirearmCard(
    ThemeController theme,
    Map<String, String> firearm,
    int index,
  ) {
    final total = barrelLifeTotal(firearm);
    final remaining = barrelLifeRemaining(firearm);
    final usedPct = barrelLifeUsedPercent(firearm);
    final validity = licenceValidity(firearm['expiry']);
    final expired = validity == 'Expired';
    int? daysToExpiry;
    if (firearm['expiry'] != null && firearm['expiry']!.isNotEmpty) {
      try {
        final dt = DateTime.parse(firearm['expiry']!);
        daysToExpiry = dt.difference(DateTime.now()).inDays;
      } catch (_) {}
    }
    final isExpiringSoon = daysToExpiry != null && daysToExpiry <= 180;
    final maintenanceDue = isMaintenanceDue(firearm);

    final photoPath = (firearm['photoPath'] ?? '').trim();
    final make = (firearm['make'] ?? '').trim();
    final model = (firearm['model'] ?? '').trim();
    final caliber = (firearm['caliber'] ?? '').trim();
    final serial = (firearm['serial'] ?? '').trim();
    final makeModel = [make, model].where((part) => part.isNotEmpty).join(' ');
    final title = makeModel.isEmpty ? 'Registered Firearm' : makeModel;

    return HunterMediaCard(
      theme: theme,
      image: photoPath.isNotEmpty ? NetworkImage(photoPath) : null,
      fallbackIcon: Icons.shield_rounded,
      title: caliber.isNotEmpty ? '$title ($caliber)' : title,
      subtitle: serial.isNotEmpty ? 'S/N: $serial' : null,
      topLeftPill: HunterMediaPill(
        icon: expired ? Icons.event_busy_rounded : Icons.verified_user_rounded,
        label:
            expired ? 'LICENCE EXPIRED' : 'LICENCE: ${validity.toUpperCase()}',
        amber: !expired,
        accentColor: expired ? Colors.redAccent : null,
      ),
      topRightActions: [
        HunterFrostedCircleButton(
          icon: Icons.add_circle_outline,
          iconColor: const Color(0xFFF5F1E8),
          tooltip: 'Log rounds',
          onPressed: () => _logRounds(firearm),
        ),
        const SizedBox(width: 6),
        HunterFrostedCircleButton(
          icon: Icons.build_rounded,
          iconColor:
              maintenanceDue ? Colors.redAccent : const Color(0xFFF5F1E8),
          tooltip: 'Maintenance',
          onPressed: () => _openMaintenance(firearm),
        ),
        if (isExpiringSoon) ...[
          const SizedBox(width: 6),
          HunterFrostedCircleButton(
            icon: Icons.autorenew_rounded,
            iconColor: Colors.orange.shade300,
            tooltip: 'Renew license',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          FirearmRenewalScreen(theme: theme, firearm: firearm),
                ),
              );
            },
          ),
        ],
      ],
      pills: [
        HunterMediaPill(
          icon: Icons.gps_fixed_rounded,
          label: caliber.isEmpty ? 'CALIBER N/A' : caliber,
          amber: true,
        ),
        HunterMediaPill(
          icon: Icons.speed_rounded,
          label:
              total > 0 ? 'Barrel: $remaining rds left' : 'Barrel life: not set',
        ),
        if (total > 0)
          HunterMediaPill(
            icon: Icons.donut_large_rounded,
            label: '$usedPct% used',
            amber: usedPct < 85,
            accentColor: usedPct >= 85 ? Colors.redAccent : null,
          ),
        if (maintenanceDue)
          HunterMediaPill(
            icon: Icons.build_rounded,
            label: 'MAINTENANCE DUE',
            accentColor: Colors.redAccent,
          ),
      ],
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => FirearmDetailScreen(
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
    );
  }

  Widget _buildVaultStatusCard(ThemeController theme) {
    return Card(
      color: HunterUi.cardColor(theme),
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
