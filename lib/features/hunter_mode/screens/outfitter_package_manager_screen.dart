import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/safe_bottom_inset.dart';
import '../models/package_pricing.dart';
import '../services/package_booking_manager.dart';
import 'outfitter_package_creator_screen.dart';

/// Outfitter "My Packages" management screen.
///
/// Reactive list of the current outfitter's published packages with lifecycle
/// status toggles (Active / Draft / Archived), inline edit, and a soft-delete
/// confirmation modal. Soft-deleted packages are excluded from the default
/// list but recoverable via the status filter.
class OutfitterPackageManagerScreen extends StatefulWidget {
  final ThemeController theme;

  const OutfitterPackageManagerScreen({super.key, required this.theme});

  @override
  State<OutfitterPackageManagerScreen> createState() =>
      _OutfitterPackageManagerScreenState();
}

class _OutfitterPackageManagerScreenState
    extends State<OutfitterPackageManagerScreen> {
  // Status filter chip. null => show all non-deleted packages.
  PackageStatus? _filter;
  bool _showDeleted = false;

  static const List<_StatusFilterChip> _filters = [
    _StatusFilterChip(label: 'All', status: null),
    _StatusFilterChip(label: 'Active', status: PackageStatus.active),
    _StatusFilterChip(label: 'Draft', status: PackageStatus.draft),
    _StatusFilterChip(label: 'Archived', status: PackageStatus.archived),
  ];

  Stream<QuerySnapshot> _stream() {
    final status = _showDeleted ? PackageStatus.deleted : _filter;
    return PackageBookingManager.instance.getMyPackagesStream(status: status);
  }

  Future<void> _setStatus(String packageId, PackageStatus status) async {
    try {
      await PackageBookingManager.instance
          .setPackageStatus(packageId: packageId, status: status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Package marked ${status.label}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update status: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Restocks a sold-out / low-stock package. Prompts the outfitter for a new
  /// slot count, then calls [PackageBookingManager.restockPackage] (which also
  /// re-activates a `sold_out` listing back to `active`).
  Future<void> _restock(String packageId, int currentQty) async {
    final controller =
        TextEditingController(text: currentQty <= 0 ? '1' : currentQty.toString());
    final qty = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text('Restock Package',
            style: TextStyle(
                color: widget.theme.textColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set the new number of bookable slots. The package will be '
              're-activated if it was sold out.',
              style: TextStyle(color: widget.theme.subtitleColor, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: widget.theme.textColor),
              decoration: InputDecoration(
                labelText: 'Available slots',
                labelStyle: TextStyle(color: widget.theme.subtitleColor),
                suffixText: 'slots',
                suffixStyle: TextStyle(color: widget.theme.subtitleColor),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, v);
            },
            child: const Text('Restock'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (qty == null || !mounted) return;
    if (qty < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Restock quantity must be at least 1 slot'),
            backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await PackageBookingManager.instance
          .restockPackage(packageId: packageId, quantityAvailable: qty);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Package restocked to $qty slot${qty == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to restock: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(String packageId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: widget.theme.cardColor,
        title: Text(
          'Delete Package?',
          style: TextStyle(
              color: widget.theme.textColor, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '"$title" will be removed from the marketplace and your package list. '
          'Existing bookings are retained. This can be reversed by restoring '
          'the package from the Deleted filter.',
          style: TextStyle(color: widget.theme.subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel',
                style: TextStyle(color: widget.theme.subtitleColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PackageBookingManager.instance.deletePackage(packageId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Package deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _editPackage(Map<String, dynamic> data, String packageId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OutfitterPackageCreatorScreen(
          theme: widget.theme,
          existingPackage: {...data, 'id': packageId},
          packageId: packageId,
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
        title: const Text('📦 My Packages',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.backgroundColor,
        foregroundColor: theme.textColor,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                OutfitterPackageCreatorScreen(theme: widget.theme),
          ),
        ),
        backgroundColor: theme.accentColor,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: Column(
        children: [
          // Status filter chips.
          Container(
            color: theme.cardColor,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._filters.map((chip) => _filterChip(theme, chip)),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Deleted',
                        style: TextStyle(
                            color: _showDeleted
                                ? Colors.white
                                : theme.subtitleColor)),
                    selected: _showDeleted,
                    onSelected: (v) =>
                        setState(() => _showDeleted = v),
                    selectedColor: Colors.red.shade700,
                    checkmarkColor: Colors.white,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Colors.green));
                }
                if (snapshot.hasError) {
                  return _emptyState(
                    theme,
                    icon: Icons.error_outline,
                    color: Colors.red,
                    message: 'Error loading packages',
                    detail:
                        'A composite Firestore index may be required. '
                        '${snapshot.error}',
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _emptyState(
                    theme,
                    icon: Icons.inbox_rounded,
                    color: theme.accentColor,
                    message: _showDeleted
                        ? 'No deleted packages'
                        : 'No packages yet',
                    detail: _showDeleted
                        ? 'Deleted packages will appear here.'
                        : 'Tap + to publish your first hunting package.',
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, SafeBottomInset.of(context)),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _packageCard(theme, data, doc.id);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(ThemeController theme, _StatusFilterChip chip) {
    final selected = !_showDeleted && _filter == chip.status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(chip.label,
            style: TextStyle(
                color: selected ? Colors.black : theme.subtitleColor)),
        selected: selected,
        onSelected: (_) => setState(() {
          _showDeleted = false;
          _filter = chip.status;
        }),
        selectedColor: theme.accentColor,
        checkmarkColor: Colors.black,
      ),
    );
  }

  Widget _packageCard(
      ThemeController theme, Map<String, dynamic> data, String packageId) {
    final title = (data['title'] ?? 'Untitled').toString();
    final status =
        PackageStatus.fromString(data['status'] as String?);
    final basePrice = (data['basePriceRands'] as num?)?.toDouble() ?? 0.0;
    final total = (data['totalPriceZAR'] as num?)?.toDouble() ??
        basePrice * (1 + PackageBookingManager.platformCommissionRate);
    final depositPct = (data['depositPercentage'] as num?)?.toDouble() ?? 25;
    final quantityAvailable =
        PackageQuantity.fromData(data['quantityAvailable']);
    final imageUrls = data['imageUrls'];
    final firstImage = imageUrls is List && imageUrls.isNotEmpty
        ? imageUrls.first as String
        : null;
    final species = data['speciesItems'];
    final speciesCount =
        species is List ? species.length : 0;

    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: firstImage != null
                        ? CachedNetworkImage(
                            imageUrl: firstImage,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => ColoredBox(
                              color: theme.backgroundColor,
                              child: const Center(
                                  child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: theme.backgroundColor,
                              child: Icon(Icons.image_rounded,
                                  color: theme.subtitleColor),
                            ),
                          )
                        : Container(
                            color: theme.backgroundColor,
                            child: Icon(Icons.terrain_rounded,
                                color: theme.subtitleColor),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'R ${total.toStringAsFixed(2)} total',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$speciesCount species • $depositPct% deposit\n'
                        '${PackageQuantity.remainingLabel(quantityAvailable)}',
                        style: TextStyle(
                            color: theme.subtitleColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _statusBadge(theme, status),
              ],
            ),
            const SizedBox(height: 12),
            // Action row. The chip group is wrapped in a horizontal
            // SingleChildScrollView so the chips stay fully visible + reachable
            // (no yellow-stripes overflow) regardless of screen width, font
            // scale, or how many chips render (e.g. sold-out adds Restock).
            // The destructive delete IconButton is kept outside the scroller so
            // it stays pinned at the trailing edge and is always reachable.
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        if (status != PackageStatus.deleted) ...[
                          _actionChip(
                            theme,
                            icon: status == PackageStatus.active
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            label: status == PackageStatus.active
                                ? 'Deactivate'
                                : 'Activate',
                            onTap: () => _setStatus(
                              packageId,
                              status == PackageStatus.active
                                  ? PackageStatus.draft
                                  : PackageStatus.active,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Restock action — shown for sold-out or low-stock packages.
                          if (status == PackageStatus.soldOut ||
                              quantityAvailable <= 0) ...[
                            _actionChip(
                              theme,
                              icon: Icons.add_shopping_cart_rounded,
                              label: 'Restock',
                              onTap: () => _restock(packageId, quantityAvailable),
                            ),
                            const SizedBox(width: 8),
                          ],
                          _actionChip(
                            theme,
                            icon: Icons.archive_outlined,
                            label: status == PackageStatus.archived
                                ? 'Unarchive'
                                : 'Archive',
                            onTap: () => _setStatus(
                              packageId,
                              status == PackageStatus.archived
                                  ? PackageStatus.draft
                                  : PackageStatus.archived,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _actionChip(
                            theme,
                            icon: Icons.edit_rounded,
                            label: 'Edit',
                            onTap: () => _editPackage(data, packageId),
                          ),
                        ] else ...[
                          _actionChip(
                            theme,
                            icon: Icons.restore_rounded,
                            label: 'Restore',
                            onTap: () => _setStatus(packageId, PackageStatus.draft),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (status != PackageStatus.deleted) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _confirmDelete(packageId, title),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(
    ThemeController theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: theme.accentColor),
      label: Text(label,
          style: TextStyle(color: theme.textColor, fontSize: 12)),
      backgroundColor: theme.backgroundColor,
      side: BorderSide(
          color: theme.accentColor.withValues(alpha: 0.3)),
    );
  }

  Widget _statusBadge(ThemeController theme, PackageStatus status) {
    final (color, label) = switch (status) {
      PackageStatus.active => (Colors.green, 'ACTIVE'),
      PackageStatus.draft => (Colors.orange, 'DRAFT'),
      PackageStatus.archived => (Colors.grey, 'ARCHIVED'),
      PackageStatus.deleted => (Colors.red, 'DELETED'),
      PackageStatus.soldOut => (Colors.red, 'SOLD OUT'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _emptyState(
    ThemeController theme, {
    required IconData icon,
    required Color color,
    required String message,
    required String detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color.withValues(alpha: 0.6), size: 56),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(
                    color: theme.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.subtitleColor, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterChip {
  final String label;
  final PackageStatus? status;
  const _StatusFilterChip({required this.label, required this.status});
}
