import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/measurement_formatter.dart';
import '../services/meat_processing_exporter.dart';
import '../services/meat_processing_order_manager.dart';

/// Lists a hunter's persisted meat-processing / slaughterhouse orders with
/// their status, and offers quick re-share of the generated manifest PDF.
class MeatProcessingOrderHistoryScreen extends StatefulWidget {
  final ThemeController theme;

  const MeatProcessingOrderHistoryScreen({super.key, required this.theme});

  @override
  State<MeatProcessingOrderHistoryScreen> createState() =>
      _MeatProcessingOrderHistoryScreenState();
}

class _MeatProcessingOrderHistoryScreenState
    extends State<MeatProcessingOrderHistoryScreen> {
  final MeatProcessingOrderManager _manager = MeatProcessingOrderManager();

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return AnimatedBuilder(
      animation: theme,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          appBar: AppBar(
            title: Text(
              'ORDER LOGS',
              style: TextStyle(
                color: theme.textColor,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 16,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: theme.accentColor),
          ),
          body: SafeArea(
            child: StreamBuilder<List<MeatProcessingOrder>>(
              stream: _manager.getMyOrdersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _StateMessage(
                    theme: theme,
                    icon: Icons.error_outline_rounded,
                    color: Colors.redAccent,
                    title: 'Could not load orders',
                    message:
                        'Orders require a Firestore index or sign-in. '
                        '${snapshot.error}',
                  );
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return _StateMessage(
                    theme: theme,
                    icon: Icons.receipt_long_outlined,
                    color: theme.accentColor,
                    title: 'No orders logged yet',
                    message:
                        'Submitted slaughterhouse orders will appear here '
                        'with their status and manifest re-share option.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _OrderCard(theme: theme, order: orders[i]),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final ThemeController theme;
  final MeatProcessingOrder order;

  const _OrderCard({required this.theme, required this.order});

  Future<void> _reshareManifest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await MeatProcessingExporter().generateAndShareManifest(
        carcassTag: order.carcassTag,
        hunterName: order.hunterName,
        species: order.species,
        hangingWeight: order.hangingWeight,
        portions: order.portions,
        spicePreference: order.spicePreference,
        specialInstructions: order.specialInstructions,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Manifest re-shared'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _changeStatus(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Update order status'),
        children: MeatProcessingOrder.statuses
            .map(
              (s) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Row(
                  children: [
                    Icon(
                      s == order.status
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: theme.accentColor,
                    ),
                    const SizedBox(width: 8),
                    Text(s),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected != null && selected != order.status) {
      try {
        await MeatProcessingOrderManager().updateOrderStatus(order.id, selected);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Collected':
        return Colors.green;
      case 'Ready for Collection':
        return Colors.teal;
      case 'Processing':
        return Colors.orange;
      case 'Acknowledged':
        return Colors.blueAccent;
      case 'Cancelled':
        return Colors.redAccent;
      default:
        return theme.subtitleColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalWeight = order.portions.fold<double>(
      0,
      (sum, p) => sum + (p.targetWeightKg ?? 0),
    );
    final dateText = order.orderTimestamp == null
        ? '--'
        : '${order.orderTimestamp!.toLocal()}'
            .replaceFirst(RegExp(r'\.\d+'), '');
    final statusColor = _statusColor(order.status);

    return Card(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.textColor.withAlpha(20), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_rounded, color: theme.accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.carcassTag.isEmpty ? 'Untitled order' : order.carcassTag,
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _changeStatus(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor, width: 1),
                    ),
                    child: Text(
                      order.status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _meta(theme, 'Species', order.species),
                _meta(
                  theme,
                  'Hanging',
                  MeasurementFormatter.instance.formatWeight(order.hangingWeight),
                ),
                _meta(
                  theme,
                  'Portions',
                  '${order.portions.length}'
                  '${totalWeight > 0 ? ' • ${totalWeight.toStringAsFixed(1)} kg' : ''}',
                ),
                if (order.spicePreference.isNotEmpty)
                  _meta(theme, 'Default spice', order.spicePreference),
                _meta(theme, 'Logged', dateText),
              ],
            ),
            if (order.portions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: order.portions.map((p) {
                  final w = p.targetWeightKg == null
                      ? '-'
                      : MeasurementFormatter.instance
                          .formatWeight(p.targetWeightKg);
                  return Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${p.name} • $w'
                      '${p.spice.isNotEmpty ? ' • ${p.spice}' : ''}',
                      style: TextStyle(
                        color: theme.textColor,
                        fontSize: 11,
                      ),
                    ),
                    backgroundColor: theme.backgroundColor,
                    side: BorderSide(
                      color: theme.accentColor.withValues(alpha: 0.3),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (order.specialInstructions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                order.specialInstructions,
                style: TextStyle(
                  color: theme.subtitleColor,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reshareManifest(context),
                    icon: Icon(Icons.picture_as_pdf_outlined,
                        size: 18, color: theme.accentColor),
                    label: Text(
                      'RE-SHARE MANIFEST',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.accentColor, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  Widget _meta(ThemeController theme, String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: theme.subtitleColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: theme.textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final ThemeController theme;
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _StateMessage({
    required this.theme,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: theme.subtitleColor, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
