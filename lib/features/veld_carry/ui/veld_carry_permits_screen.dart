import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:jagspoor/core/services/image_service.dart';
import 'package:jagspoor/core/theme/app_theme.dart';
import 'package:jagspoor/core/widgets/copyright_footer.dart';
import 'package:jagspoor/core/widgets/safe_bottom_inset.dart';
import 'package:jagspoor/features/outfitter_mode/widgets/outfitter_scaffold.dart';
import 'package:jagspoor/features/veld_carry/models/camp.dart';
import 'package:jagspoor/features/veld_carry/models/farm_permit.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_permit_form_screen.dart';
import 'package:jagspoor/features/veld_carry/ui/veld_carry_ui_common.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_calculator.dart';
import 'package:jagspoor/features/veld_carry/veld_carry_repository.dart';

/// The outfitter's permits vault for one farm.
///
/// Reached only through `VeldCarryGate` (farm card "Permits" button and the
/// camp detail "Permits" action) — so with the feature flag OFF none of this UI
/// can appear. Status badges are produced by
/// `veld_carry_calculator.dart` (`permitStatus`).
class VeldCarryPermitsScreen extends StatefulWidget {
  const VeldCarryPermitsScreen({
    super.key,
    required this.farmId,
    this.farmName,
    this.theme,
    this.repository,
    this.currentUidOverride,
  });

  final String farmId;
  final String? farmName;
  final ThemeController? theme;
  final VeldCarryRepository? repository;

  /// Test seam: pins the signed-in uid so widget tests can drive the screen
  /// against a fake Firestore without a Firebase app.
  @visibleForTesting
  final String? currentUidOverride;

  @override
  State<VeldCarryPermitsScreen> createState() => _VeldCarryPermitsScreenState();
}

class _VeldCarryPermitsScreenState extends State<VeldCarryPermitsScreen> {
  late final ThemeController _theme = widget.theme ?? ThemeController.instance;
  late final VeldCarryRepository _repository =
      widget.repository ?? VeldCarryRepository.instance;

  bool _loading = true;
  String? _error;
  List<FarmPermit> _permits = const [];
  List<Camp> _camps = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _currentUid() {
    final override = widget.currentUidOverride;
    if (override != null) return override;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view permits.';
      });
      return;
    }
    try {
      final permits = await _repository.getPermits(uid, widget.farmId);
      List<Camp> camps = const [];
      try {
        camps = await _repository.getCamps(uid, widget.farmId);
      } catch (e) {
        // The camp multi-select is a convenience; a camp read failure must not
        // hide the permits themselves.
        debugPrint(
          'VeldCarryPermitsScreen: camp read failed for farm '
          '${widget.farmId}: $e',
        );
      }
      if (!mounted) return;
      setState(() {
        _permits = permits;
        _camps = camps;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load permits: $e';
      });
    }
  }

  Future<void> _openForm({FarmPermit? permit}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VeldCarryPermitFormScreen(
          farmId: widget.farmId,
          farmName: widget.farmName,
          existingPermit: permit,
          camps: _camps,
          theme: _theme,
          repository: _repository,
          currentUidOverride: widget.currentUidOverride,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<bool> _confirmDelete(FarmPermit permit) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${permitTypeLabel(permit.permitType)}?'),
        content: const Text(
          'This removes the permit from the farm vault. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _delete(FarmPermit permit) async {
    final uid = _currentUid();
    if (uid == null) return;
    final confirmed = await _confirmDelete(permit);
    if (!confirmed) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _repository.deletePermit(uid, widget.farmId, permit.id);
      // Best-effort Storage cleanup. A failed object delete (already gone, a
      // permission change, offline) is logged and never fails the Firestore
      // delete that already succeeded.
      if (permit.fileUrl != null && permit.fileUrl!.isNotEmpty) {
        final removed =
            await ImageService.deleteByDownloadUrl(permit.fileUrl);
        if (!removed) {
          debugPrint(
            'VeldCarryPermits: Storage cleanup skipped for ${permit.id} '
            '(file may already be gone).',
          );
        }
      }
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('${permitTypeLabel(permit.permitType)} deleted.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Could not delete permit: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Scaffold(
      backgroundColor: theme.backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Permits Vault',
              style: TextStyle(
                color: OutfitterUi.titleColor(theme),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (widget.farmName != null && widget.farmName!.isNotEmpty)
              Text(
                widget.farmName!,
                style: TextStyle(
                  color: OutfitterUi.subtitleColor(theme),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.accentColor),
        elevation: 0,
        actions: [
          OutfitterActionChip(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh permits',
            iconColor: theme.accentColor,
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: OutfitterBushveldBackground.stack(
        fallbackColor: theme.backgroundColor,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(theme),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('veldPermitAddButton'),
        backgroundColor: theme.accentColor,
        foregroundColor: Colors.white,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Permit',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeController theme) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.green),
      );
    }
    if (_error != null) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [_errorState(theme, _error!)],
      );
    }
    if (_permits.isEmpty) {
      return ListView(
        padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
        children: [
          _emptyState(theme),
          const CopyrightFooter(),
        ],
      );
    }
    return ListView.builder(
      padding: SafeBottomInset.paddingFor(context, horizontal: 16, top: 16),
      itemCount: _permits.length + 1,
      itemBuilder: (context, index) {
        if (index == _permits.length) return const CopyrightFooter();
        return _permitCard(theme, _permits[index]);
      },
    );
  }

  Widget _permitCard(ThemeController theme, FarmPermit permit) {
    final status = permitStatus(permit.expiryDate);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: ValueKey('veldPermitCard_${permit.id}'),
        padding: const EdgeInsets.all(14),
        decoration: OutfitterUi.cardDecoration(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    permitTypeLabel(permit.permitType),
                    style: TextStyle(
                      color: theme.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                VeldCarryBadge(
                  key: ValueKey('veldPermitStatus_${permit.id}'),
                  label: permitStatusLabel(status),
                  color: permitStatusColor(status),
                  darkMode: theme.isDarkMode,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _infoRow(theme, 'Permit number', permit.permitNumber),
            _infoRow(theme, 'Issued by', permit.issuingAuthority),
            _infoRow(theme, 'Province', permit.province),
            _infoRow(theme, 'Expires', formatPermitDate(permit.expiryDate)),
            if (permit.fileName != null && permit.fileName!.isNotEmpty)
              _infoRow(theme, 'Attachment', permit.fileName!),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                VeldCarryBadge(
                  key: ValueKey('veldPermitVisibility_${permit.id}'),
                  label: permitVisibilityLabel(permit.visibility),
                  color: permit.visibility ==
                          FarmPermit.visibilityHunterVisible
                      ? theme.accentColor
                      : const Color(0xFF6D4C41),
                  icon: permit.visibility ==
                          FarmPermit.visibilityHunterVisible
                      ? Icons.visibility_outlined
                      : Icons.lock_outline_rounded,
                  darkMode: theme.isDarkMode,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  key: ValueKey('veldPermitEdit_${permit.id}'),
                  onPressed: () => _openForm(permit: permit),
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: theme.accentColor,
                  ),
                  label: Text(
                    'EDIT',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: ValueKey('veldPermitDelete_${permit.id}'),
                  onPressed: () => _delete(permit),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 16,
                    color: Colors.red.shade700,
                  ),
                  label: Text(
                    'DELETE',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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

  Widget _infoRow(ThemeController theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: OutfitterUi.subtitleColor(theme),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeController theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(
            Icons.folder_shared_outlined,
            size: 42,
            color: theme.accentColor,
          ),
          const SizedBox(height: 12),
          Text(
            'No permits captured yet',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add the farm\'s regulatory and compliance permits here. Mark a '
            'permit "Hunter visible" to share its type, expiry and status '
            'with hunters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(ThemeController theme, String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: OutfitterUi.cardDecoration(theme),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 42, color: theme.accentColor),
          const SizedBox(height: 12),
          Text(
            'Could not load permits',
            style: TextStyle(
              color: theme.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OutfitterUi.subtitleColor(theme),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _load,
            style: FilledButton.styleFrom(
              backgroundColor: theme.accentColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}
