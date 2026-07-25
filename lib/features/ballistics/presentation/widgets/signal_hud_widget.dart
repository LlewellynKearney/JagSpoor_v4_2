import 'dart:async';
import 'package:flutter/material.dart';
import '../../outfitter_mode/data/services/outfitter_sync_service.dart';

/// A lightweight widget that consumes stream-driven OutfitterSyncService status alerts.
/// Displays a sync indicator showing pending record count.
/// 
/// When unsynced items remain (isDirty == 1), renders a status block in
/// Thermal Glow text highlighting the pending count.
/// Triggers a smooth green fade once synced.
class SignalHudWidget extends StatefulWidget {
  /// The sync service to consume status from.
  final OutfitterSyncService syncService;
  
  /// Whether to show a static header block (true) or inline widget (false).
  final bool isHeaderBlock;
  
  /// Callback when sync is complete.
  final VoidCallback? onSynced;
  
  /// Callback when user taps sync button.
  final VoidCallback? onSyncRequested;

  const SignalHudWidget({
    super.key,
    required this.syncService,
    this.isHeaderBlock = true,
    this.onSynced,
    this.onSyncRequested,
  });

  @override
  State<SignalHudWidget> createState() => _SignalHudWidgetState();
}

class _SignalHudWidgetState extends State<SignalHudWidget>
    with SingleTickerProviderStateMixin {
  late StreamSubscription<int> _subscription;
  int _pendingCount = 0;
  bool _isSyncing = false;
  bool _justSynced = false;
  
  // Animation controller for fade effect
  late AnimationController _fadeController;
  late Animation<Color?> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _fadeAnimation = ColorTween(
      begin: const Color(0xFF4CAF50), // Green
      end: const Color(0xFFC5A059), // Thermal Glow
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
    
    // Subscribe to sync status stream
    _subscription = widget.syncService.dirtyCountStream.listen((count) {
      setState(() {
        _pendingCount = count;
        if (count == 0 && _pendingCount > 0) {
          // Trigger sync complete animation
          _justSynced = true;
          _fadeController.forward(from: 0);
          widget.onSynced?.call();
        }
      });
    });
    
    // Initial status check
    widget.syncService.checkSyncStatus();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      await widget.syncService.syncAll();
      widget.onSyncRequested?.call();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _pendingCount > 0;
    
    if (widget.isHeaderBlock) {
      return _buildHeaderBlock(hasPending);
    }
    
    return _buildInlineWidget(hasPending);
  }

  Widget _buildHeaderBlock(bool hasPending) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: hasPending
            ? const Color(0xFF8B4513).withValues(alpha: 0.4)
            : const Color(0xFF1A1A1A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasPending
              ? const Color(0xFFC5A059)
              : const Color(0xFFC5A059).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSyncIcon(hasPending),
          const SizedBox(width: 8),
          _buildStatusText(hasPending),
          if (hasPending) ...[
            const SizedBox(width: 12),
            _buildSyncButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildInlineWidget(bool hasPending) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSyncIcon(hasPending),
        const SizedBox(width: 8),
        _buildStatusText(hasPending),
        if (hasPending) ...[
          const SizedBox(width: 8),
          _buildSyncButton(),
        ],
      ],
    );
  }

  Widget _buildSyncIcon(bool hasPending) {
    if (_isSyncing) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFC5A059),
        ),
      );
    }
    
    if (_justSynced) {
      return AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Icon(
            Icons.cloud_done,
            size: 18,
            color: _fadeAnimation.value ?? const Color(0xFFC5A059),
          );
        },
      );
    }
    
    if (hasPending) {
      return const Icon(
        Icons.cloud_off,
        size: 18,
        color: Color(0xFFC5A059),
      );
    }
    
    return const Icon(
      Icons.cloud_done,
      size: 18,
      color: Color(0xFFC5A059),
    );
  }

  Widget _buildStatusText(bool hasPending) {
    if (_justSynced) {
      return AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Text(
            'SYNCED',
            style: TextStyle(
              color: _fadeAnimation.value ?? const Color(0xFFC5A059),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          );
        },
      );
    }
    
    if (hasPending) {
      return Text(
        '⚠️ [$_pendingCount RECORD${_pendingCount > 1 ? 'S' : ''} PENDING SYNC]',
        style: const TextStyle(
          color: Color(0xFFC5A059),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      );
    }
    
    return const Text(
      'ALL SYNCED',
      style: TextStyle(
        color: Color(0xFFC5A059),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSyncButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSyncing ? null : _handleSync,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFC5A059).withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isSyncing ? Icons.sync : Icons.sync_disabled,
                size: 14,
                color: const Color(0xFFC5A059),
              ),
              const SizedBox(width: 4),
              Text(
                _isSyncing ? 'SYNCING...' : 'SYNC',
                style: const TextStyle(
                  color: Color(0xFFC5A059),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact version of the SignalHudWidget for use in app bars.
class SignalHudIcon extends StatelessWidget {
  final OutfitterSyncService syncService;
  final VoidCallback? onTap;

  const SignalHudIcon({
    super.key,
    required this.syncService,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: syncService.dirtyCountStream,
      initialData: syncService.dirtyCount,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final hasPending = count > 0;
        
        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                hasPending ? Icons.cloud_off : Icons.cloud_done,
                color: const Color(0xFFC5A059),
              ),
              if (hasPending)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFC5A059),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      count > 9 ? '9+' : count.toString(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: onTap,
          tooltip: hasPending
              ? '$count record${count > 1 ? 's' : ''} pending sync'
              : 'All synced',
        );
      },
    );
  }
}
