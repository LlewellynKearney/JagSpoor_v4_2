import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/copyright_footer.dart';
import '../data/services/optic_log_service.dart';

/// "View Optic History" surface for the Optical Suite. Renders a reactive,
/// newest-first log of the user's optic-profile save events so they can
/// review their saved optics and configuration changes over time. Each entry
/// shows the host firearm label, the optic identity, turret units, focal
/// plane, reticle, and a timestamp.
class OpticHistoryScreen extends StatelessWidget {
  const OpticHistoryScreen({super.key, required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      appBar: AppBar(
        backgroundColor: theme.backgroundColor,
        title: Text(
          'OPTIC HISTORY',
          style: TextStyle(
            color: theme.accentColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            fontSize: 15,
          ),
        ),
        iconTheme: IconThemeData(color: theme.textColor),
      ),
      body: StreamBuilder<List<OpticLogEntry>>(
        stream: OpticLogService.instance.getMyOpticLogsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StateBanner(
              icon: Icons.cloud_off,
              message: 'Could not load optic history.',
              detail: '${snapshot.error}',
              theme: theme,
            );
          }
          final entries = snapshot.data ?? const <OpticLogEntry>[];
          if (entries.isEmpty) {
            return _StateBanner(
              icon: Icons.history,
              message: 'No optic saves logged yet.',
              detail:
                  'Save an optic profile from the Optical Suite to start your audit log.',
              theme: theme,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _OpticLogCard(
              entry: entries[i],
              theme: theme,
            ),
          );
        },
      ),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: CopyrightFooter.tight(),
      ),
    );
  }
}

class _OpticLogCard extends StatelessWidget {
  const _OpticLogCard({required this.entry, required this.theme});

  final OpticLogEntry entry;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final optic = entry.optic;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.center_focus_strong,
                    color: theme.accentColor, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    optic.opticName.isEmpty
                        ? 'Unnamed optic'
                        : optic.opticName,
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  _formatTimestamp(entry.savedAt),
                  style: TextStyle(
                    color: theme.subtitleColor,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _DetailRow(
                label: 'Firearm', value: entry.firearmLabel, theme: theme),
            _DetailRow(
                label: 'Turret',
                value: '${optic.turretUnitLabel} • ${optic.clickValueLabel}',
                theme: theme),
            _DetailRow(
                label: 'Focal plane', value: optic.focalPlaneLabel, theme: theme),
            _DetailRow(
                label: 'Reticle', value: optic.reticleType, theme: theme),
            _DetailRow(
                label: 'Magnification',
                value:
                    '${optic.currentMagnification.toStringAsFixed(0)}x (native ${optic.nativeMagnification.toStringAsFixed(0)}x)',
                theme: theme),
            _DetailRow(
                label: 'Tube / HOB',
                value:
                    '${optic.tubeDiameterMm.toStringAsFixed(0)} mm / ${optic.heightOverBoreInches.toStringAsFixed(2)} in',
                theme: theme),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.label, required this.value, required this.theme});
  final String label;
  final String value;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: theme.subtitleColor, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: theme.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  const _StateBanner({
    required this.icon,
    required this.message,
    required this.detail,
    required this.theme,
  });
  final IconData icon;
  final String message;
  final String detail;
  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.subtitleColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
